// functions/index.js

// Global options for Gen2 functions
const { setGlobalOptions } = require('firebase-functions/v2');
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onRequest } = require('firebase-functions/v2/https');
const { onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

/**
 * Push notify when a doc is created at:
 *   /users/{uid}/inbox/{msgId}
 *
 * Expected inbox doc shape (examples):
 * {
 *   title: "New Alert",
 *   body: "Weld #A12 rejected",
 *   type: "alert" | "chat",
 *   schemaId: "visual_inspection",
 *   reportId: "abc123"
 * }
 *
 * Client tokens must be saved under:
 *   /users/{uid}/profile/info.fcmTokens = [token1, token2, ...]
 */
exports.notifyOnInboxCreate = onDocumentCreated(
  'users/{uid}/inbox/{msgId}',
  async (event) => {
    const { uid } = event.params;
    const data = event.data?.data() || {};

     // Add createdAt if not present
    if (!data.createdAt) {
      await event.data.ref.update({
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    // Increment unread counter
    const metaRef = db.collection('users').doc(uid).collection('meta').doc('meta');
    await metaRef.set(
      { inboxUnread: admin.firestore.FieldValue.increment(1) },
      { merge: true }
    );

    // Load recipient tokens
    const prof = await db
      .collection('users')
      .doc(uid)
      .collection('profile')
      .doc('info')
      .get();

    const tokens = Array.isArray(prof.data()?.fcmTokens) ? prof.data().fcmTokens.filter(Boolean) : [];
    if (!tokens.length) return;

    // Compose notification
    const title = data.title || 'New notification';
    const body  = data.body  || data.subtitle || 'You have a new message';
    const message = {
      tokens,
      notification: { title, body },
      data: {
        type: String(data.type || 'alert'),
        schemaId: String(data.schemaId || ''),
        reportId: String(data.reportId || ''),
      },
    };

    // Send
    await admin.messaging().sendEachForMulticast(message).catch(() => {});
  }
);

// ============================================
// STRIPE PAYMENT FUNCTIONS
// ============================================

const { defineSecret } = require('firebase-functions/params');

// Define secrets for Stripe (more secure than config)
const stripeSecretKey = defineSecret('STRIPE_SECRET_KEY');
const stripeWebhookSecret = defineSecret('STRIPE_WEBHOOK_SECRET');

// Initialize Stripe (lazy load to avoid errors if secrets not set)
let stripe;
function getStripe() {
  if (!stripe) {
    stripe = require('stripe')(stripeSecretKey.value());
  }
  return stripe;
}

/**
 * Create Stripe Checkout Session for pay-per-report
 * Called from Flutter: PaymentService.buyReports()
 */
exports.createCheckoutSession = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    if (!request.auth) {
      throw new Error('User must be authenticated');
    }

    const userId = request.auth.uid;
    const userEmail = request.auth.token.email;
    const { priceId, credits } = request.data;

    if (!priceId || !credits) {
      throw new Error('priceId and credits are required');
    }

    try {
      const stripeClient = getStripe();
      const session = await stripeClient.checkout.sessions.create({
        payment_method_types: ['card'],
        mode: 'payment',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `https://weldqai.com/payment-success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `https://weldqai.com/payment-cancel`,
        metadata: {
          userId: userId,
          credits: credits.toString(),
          type: 'credits',
        },
        customer_email: userEmail,
      });

      console.log(`✅ Checkout session created for user ${userId}`);
      return { sessionId: session.id, url: session.url };
    } catch (error) {
      console.error('Error creating checkout session:', error.message);
      throw new Error('Unable to create checkout session: ' + error.message);
    }
  }
);

/**
 * Create Stripe Checkout Session for monthly subscription
 * Called from Flutter: PaymentService.subscribe()
 */
exports.createSubscription = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    // Verify user is authenticated
    if (!request.auth) {
      throw new Error('User must be authenticated');
    }

    const userId = request.auth.uid;
    const { priceId } = request.data;

    // Validate inputs
    if (!priceId) {
      throw new Error('priceId is required');
    }

    try {
      const stripeClient = getStripe();

      const session = await stripeClient.checkout.sessions.create({
        payment_method_types: ['card'],
        mode: 'subscription',
        line_items: [
          {
            price: priceId,
            quantity: 1,
          },
        ],
        success_url: `https://weldqai.com/payment-success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `https://weldqai.com/payment-cancel`,
        metadata: {
          userId: userId,
          type: 'subscription',
        },
        customer_email: request.auth.token.email,
      });

      return {
        sessionId: session.id,
        url: session.url,
      };
    } catch (error) {
      console.error('Error creating subscription:', error);
      throw new Error('Unable to create subscription: ' + error.message);
    }
  }
);

/**
 * Stripe Webhook Handler
 * Receives events from Stripe when payments complete
 * URL: https://stripewebhook-xaik6q67cq-uc.a.run.app
 */
exports.stripeWebhook = onRequest(
  { secrets: [stripeSecretKey, stripeWebhookSecret] },
  async (req, res) => {
    const sig = req.headers['stripe-signature'];
    let event;

    try {
      const stripeClient = getStripe();
      
      // Verify webhook signature
      event = stripeClient.webhooks.constructEvent(
        req.rawBody,
        sig,
        stripeWebhookSecret.value()
      );
    } catch (err) {
      console.error('Webhook signature verification failed:', err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    // Handle different event types
    try {
      switch (event.type) {
        case 'checkout.session.completed':
          await handleCheckoutComplete(event.data.object);
          break;

        case 'customer.subscription.deleted':
          await handleSubscriptionCancelled(event.data.object);
          break;

        case 'customer.subscription.updated':
          await handleSubscriptionUpdated(event.data.object);
          break;

        case 'invoice.payment_failed':
          await handlePaymentFailed(event.data.object);
          break;

        default:
          console.log(`Unhandled event type: ${event.type}`);
      }

      res.json({ received: true });
    } catch (error) {
      console.error('Error handling webhook:', error);
      res.status(500).send('Webhook handler error');
    }
  }
);

/**
 * Create Billing Portal Session
 * Allows users to manage their subscription
 */
exports.createBillingPortalSession = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    if (!request.auth) {
      throw new Error('User must be authenticated');
    }

    const userId = request.auth.uid;

    try {
      // Get user's Stripe customer ID
      const subscriptionDoc = await db
        .collection('users')
        .doc(userId)
        .collection('subscription')
        .doc('info')
        .get();

      const customerId = subscriptionDoc.data()?.stripeCustomerId;

      if (!customerId) {
        throw new Error('No active subscription found');
      }

      const stripeClient = getStripe();

      // Create billing portal session
      const session = await stripeClient.billingPortal.sessions.create({
        customer: customerId,
        return_url: 'https://weldqai.com/account',
      });

      return {
        url: session.url,
      };
    } catch (error) {
      console.error('Error creating billing portal session:', error);
      throw new Error('Unable to create billing portal session: ' + error.message);
    }
  }
);

// ============================================
// WEBHOOK EVENT HANDLERS
// ============================================

async function handleCheckoutComplete(session) {
  const userId = session.metadata.userId;
  const type = session.metadata.type;

  if (!userId) {
    console.error('No userId in session metadata');
    return;
  }

  // ✅ CRITICAL FIX - Only process if payment succeeded
  if (session.payment_status !== 'paid') {
    console.log(`⚠️ Payment not completed. Status: ${session.payment_status}, Session: ${session.id}`);
    return;
  }

  console.log(`✅ Payment confirmed as PAID for user ${userId}`);

  if (type === 'credits') {
    // ❌ NO CHANGES - Credits code stays exactly as-is
    const credits = parseInt(session.metadata.credits);
    const amount = session.amount_total / 100;

    await db
      .collection('users')
      .doc(userId)
      .collection('subscription')
      .doc('credits')
      .set(
        {
          reportCredits: admin.firestore.FieldValue.increment(credits),
          purchaseHistory: admin.firestore.FieldValue.arrayUnion({
            credits: credits,
            paymentId: session.payment_intent,
            purchasedAt: new Date().toISOString(),
            amount: amount,
            currency: session.currency,
          }),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    console.log(`✅ Added ${credits} credits to user ${userId}`);
    
  } else if (type === 'subscription') {
    // ✅ UPDATED - Add billing period for monthly subscription
    const stripeClient = getStripe();
    const subscription = await stripeClient.subscriptions.retrieve(session.subscription);

    await db
      .collection('users')
      .doc(userId)
      .collection('subscription')
      .doc('info')
      .set({
        hasAccess: true,
        status: 'active',
        subscriptionType: 'monthly_individual',
        stripeSubscriptionId: session.subscription,
        stripeCustomerId: session.customer,
        
        // ✅ NEW - Add billing period info
        currentPeriodStart: admin.firestore.Timestamp.fromMillis(subscription.current_period_start * 1000),
        currentPeriodEnd: admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000),
        cancelAtPeriodEnd: subscription.cancel_at_period_end,
        
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    // Mark trial as converted
    await db
      .collection('users')
      .doc(userId)
      .collection('subscription')
      .doc('trial')
      .update({
        status: 'converted',
        convertedAt: admin.firestore.FieldValue.serverTimestamp(),
        convertedTo: 'monthly_individual',
      });

    console.log(`✅ Created subscription for user ${userId}, renews: ${new Date(subscription.current_period_end * 1000).toISOString()}`);
  }
}

async function handleSubscriptionCancelled(subscription) {
  // Find user by Stripe subscription ID
  const snapshot = await db
    .collectionGroup('subscription')
    .where('stripeSubscriptionId', '==', subscription.id)
    .get();

  if (snapshot.empty) {
    console.error(`No user found for subscription ${subscription.id}`);
    return;
  }

  const doc = snapshot.docs[0];
  const userId = doc.ref.parent.parent.id;

  await db
    .collection('users')
    .doc(userId)
    .collection('subscription')
    .doc('info')
    .update({
      status: 'cancelled',
      hasAccess: false,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  console.log(`❌ Cancelled subscription for user ${userId}`);
}

async function handleSubscriptionUpdated(subscription) {
  // Find user by Stripe subscription ID
  const snapshot = await db
    .collectionGroup('subscription')
    .where('stripeSubscriptionId', '==', subscription.id)
    .get();

  if (snapshot.empty) {
    return;
  }

  const doc = snapshot.docs[0];
  const userId = doc.ref.parent.parent.id;

  // ✅ UPDATED - Include billing period info
  await db
    .collection('users')
    .doc(userId)
    .collection('subscription')
    .doc('info')
    .update({
      status: subscription.status,
      hasAccess: subscription.status === 'active',
      
      // ✅ NEW - Update billing period
      currentPeriodStart: admin.firestore.Timestamp.fromMillis(subscription.current_period_start * 1000),
      currentPeriodEnd: admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000),
      cancelAtPeriodEnd: subscription.cancel_at_period_end,
      
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  console.log(`🔄 Updated subscription for user ${userId}: ${subscription.status}, renews: ${new Date(subscription.current_period_end * 1000).toISOString()}`);
}

async function handlePaymentFailed(invoice) {
  const customerId = invoice.customer;

  // Find user by Stripe customer ID
  const snapshot = await db
    .collectionGroup('subscription')
    .where('stripeCustomerId', '==', customerId)
    .get();

  if (snapshot.empty) {
    return;
  }

  const doc = snapshot.docs[0];
  const userId = doc.ref.parent.parent.id;

  // Mark subscription as past_due
  await db
    .collection('users')
    .doc(userId)
    .collection('subscription')
    .doc('info')
    .update({
      status: 'past_due',
      hasAccess: false,
      lastPaymentFailed: admin.firestore.FieldValue.serverTimestamp(),
    });

  console.log(`⚠️ Payment failed for user ${userId}`);
}