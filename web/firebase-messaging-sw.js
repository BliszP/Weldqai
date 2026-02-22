
// web/firebase-messaging-sw.js

// Use compat builds (works with FlutterFire)
importScripts('https://www.gstatic.com/firebasejs/10.12.3/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.3/firebase-messaging-compat.js');

// Load Firebase config from the same gitignored file used by index.html.
// self.firebaseConfig is set by firebase-config.js (see firebase-config.js.example).
importScripts('/firebase-config.js');

firebase.initializeApp(self.firebaseConfig);

// Initialize messaging in the SW context
const messaging = firebase.messaging();

// Display a notification for background messages
messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || 'WeldQAi';
  const body  = payload?.notification?.body  || 'You have a new message';
  self.registration.showNotification(title, { body, data: payload?.data || {} });
});

// Focus an existing tab or open the app when a notification is clicked
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(windowClients => {
    for (const client of windowClients) {
      if ('focus' in client) return client.focus();
    }
    if (clients.openWindow) return clients.openWindow('/');
  }));
});
