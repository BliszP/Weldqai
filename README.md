# WeldQAi

Mobile-first SaaS application for welding and industrial QA/QC inspection management.
Built for inspectors, welding engineers, and NDT technicians in the oil & gas, construction,
and manufacturing sectors.

---

## Overview

WeldQAi enables field inspection teams to:
- Create, complete, and submit inspection reports from mobile or web
- Use schema-driven dynamic forms for any inspection type (welding, NDT, coating, hydrotest, etc.)
- Upload custom Excel or PDF templates and map them to structured data fields
- Export reports as branded PDF or Excel documents
- Collaborate with team members and share project access
- Track KPI dashboards and visualisations across projects
- Operate with offline support and background sync

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile / Web | Flutter 3.x (Material 3, Dart ^3.8.1) |
| Backend | Firebase (Firestore, Auth, Storage, Functions, FCM) |
| Payments | Stripe (Checkout + Subscriptions via Cloud Functions) |
| Cloud Functions | Node.js Gen2 (Firebase Functions v2) |
| Analytics | Firebase Analytics + Firebase Performance |
| Error Tracking | Sentry |
| Push Notifications | Firebase Cloud Messaging |
| OCR / Scanning | Google ML Kit Text Recognition |
| PDF Generation | pdf + printing packages |
| Excel Generation | excel package |
| Template Parsing | syncfusion_flutter_pdf + excel |

---

## Project Structure

```
lib/
├── main.dart                     Entry point, Firebase init, App Check
├── firebase_options.dart         Platform Firebase config (FlutterFire generated — gitignored)
│
├── app/
│   ├── router.dart               Named route map + auth guards
│   ├── app_theme.dart            Material 3 light/dark theme
│   └── constants/paths.dart      Route name constants (single source of truth)
│
├── core/
│   ├── models/                   Data transfer objects
│   ├── repositories/             Firestore data access layer
│   ├── services/                 Business logic, integrations
│   └── providers/                Flutter state (WorkspaceProvider)
│
├── features/                     Screen-level feature modules
│   ├── auth/                     Login + registration
│   ├── welcome/                  Landing screen
│   ├── account/                  Settings, profile, subscription
│   ├── reports/                  Dynamic forms, catalog, scanning
│   ├── projects/                 Project dashboard
│   ├── sharing/                  Invite and access management
│   ├── chat/                     In-app project messaging
│   ├── notifications/            Push notification inbox
│   └── visualization/            KPI charts and dashboards
│
├── screens/                      Multi-feature screens (field mapping wizard)
└── widgets/                      Shared widgets (photo, signature modals)
```

**45 active Dart files.** 58 dead files removed in the v6 cleanup (Feb 2026).
Offline UI preserved in `archive/offline_ui/` for future wiring.

---

## Firebase Services Used

| Service | Purpose |
|---|---|
| Firestore | Primary database, offline persistence |
| Firebase Auth | Email/password + Google Sign-In |
| Firebase Storage | Report photos, signatures, branding logos |
| Cloud Functions (Gen2) | Stripe payment processing, webhook handling |
| App Check | API abuse prevention (Play Integrity Android, ReCaptcha web) |
| Firebase Analytics | User behaviour tracking |
| Firebase Performance | Custom traces for template parsing, export |
| Firebase Cloud Messaging | Push notifications |

---

## Key Features

- **Schema-driven inspection forms** — Any form type rendered from JSON schema; no new code needed per form type
- **Custom template upload** — Upload existing Excel/PDF forms; ML Kit + syncfusion extracts fields; user maps them interactively
- **PDF & Excel export** — Branded reports with logos, signatures, metadata headers
- **Stripe billing** — 3 tiers: single report ($3), 5-pack ($14), monthly unlimited ($50)
- **Offline sync** — Firestore local persistence; background sync service reads correct nested collection path
- **Collaboration** — Share project access; role-based viewing
- **OCR scanning** — Scan barcodes and text directly into form fields
- **KPI dashboards** — Pass rates, throughput, defect pareto, repair metrics
- **Formula fields** — Calculated columns in tables using custom formula engine
- **Subscription caching** — Real-time `watchStatus()` stream cached in `WorkspaceProvider`; no redundant Firestore reads

---

## Security

| Layer | Implementation |
|---|---|
| App Check | Play Integrity (release) / Debug provider (debug only) — prevents API abuse |
| Firestore rules | Per-user subcollection rules; collaborator access via `isCollaborator()` helper |
| Storage rules | Per-user path isolation; collaborator read via `firestore.get()` check |
| Payments | `hasAccess` written server-side only by Stripe webhook — no client-side bypass |
| Secrets | Stripe keys in Firebase Secret Manager; never in client code |

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Android Studio or VS Code with Flutter extension
- Firebase CLI (`npm install -g firebase-tools`)
- Node.js 18+ (for Cloud Functions)

### Local Setup

```bash
# Install Flutter dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Build debug APK
flutter build apk --debug
```

### Firebase Setup

`firebase_options.dart` and `google-services.json` are gitignored.
Obtain them from your team's secure store, then place:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

To regenerate for a new Firebase project:
```bash
flutterfire configure
```

### Cloud Functions

```bash
cd functions
npm install

# Set Stripe secrets (required before first deploy)
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

firebase deploy --only functions
```

### Deploy Firebase Rules

```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
```

---

## Environment Notes

- Stripe keys stored in Firebase Secret Manager via `defineSecret()` in `functions/index.js`
- Android NDK: 27.0.12077973 (`android/app/build.gradle.kts`)
- minSdkVersion: 23 (required by firebase-auth)
- Core library desugaring enabled (`desugar_jdk_libs:2.1.4`)
- Sentry DSN passed at build time: `--dart-define=SENTRY_DSN=https://...`

---

## Open Items

| Priority | Issue |
|---|---|
| P1.5 | iOS bundle ID is still `com.example.weldqaiApp` — update via `flutterfire configure` |
| P2.1 | Migrate `provider` → Riverpod |
| P2.2 | Split `DynamicReportForm` god widget (1,426 lines) into composable widgets |
| P3.x | Enterprise: server-side enforcement, multi-tenancy, REST API, SSO |

See `docs/FIXES_REQUIRED.md` for the full prioritised tracker.

---

## Architecture Decisions

**Why Flutter?** Cross-platform (Android + iOS + Web) from a single codebase. Critical for
field inspectors using varied devices and for web-based reporting dashboards.

**Why Firebase?** Offline-first Firestore with conflict-free sync. Real-time listeners for
collaboration. Serverless scaling. Firebase Auth handles multi-provider authentication.

**Why schema-driven forms?** The QA/QC domain has hundreds of inspection form types.
Hardcoding each as a widget class (as was done historically — those files are now deleted)
is unsustainable. JSON schemas stored in Firestore allow new form types without app updates.

**Why Stripe + Cloud Functions?** Client-side payment processing is insecure. Cloud Functions
enforce server-side credit grants and subscription state, with Stripe webhook verification.

---

## Contributing

See `CLAUDE.md` for the AI development guide, architectural rules, and things not to do.
Read it fully before making any changes.
