# WeldQAi — Fixes & Play Store Checklist

Last updated: February 2026
Source: Full codebase audit + import chain analysis (Feb 2026)

---

## Play Store Launch Checklist

Track every item needed before submitting to Google Play.

### Code / Build

| # | Item | Status | Notes |
|---|---|---|---|
| B1 | `targetSdk = 35` | ✅ Done | `android/app/build.gradle.kts` |
| B2 | Release signing config (key.properties) | ✅ Done | Falls back to debug if key.properties absent |
| B3 | **Generate upload keystore** | ⬜ You do | `keytool -genkey … -keystore android/app/upload-keystore.jks` |
| B4 | **Create `android/key.properties`** | ⬜ You do | Copy from `android/key.properties.example`, fill passwords |
| B5 | **Change `applicationId`** from `com.example.weldqai_app` | ⬜ You do | Must match Firebase registration. See note in `build.gradle.kts` |
| B6 | **Register new package in Firebase Console** | ⬜ You do | Project Settings → Android apps → Add app |
| B7 | **Update `GOOGLE_SERVICES_JSON` GitHub Secret** | ⬜ You do | Download new `google-services.json` after B6 |
| B8 | iOS bundle ID placeholder `com.example.weldqaiApp` | ⬜ P1.5 | Needs Apple bundle ID + `flutterfire configure` |
| B9 | CI build Android debug | ✅ Done | `.github/workflows/ci.yml` green |
| B10 | `flutter analyze --fatal-warnings` clean | ✅ Done | 0 issues |

### Firebase / Backend

| # | Item | Status | Notes |
|---|---|---|---|
| F1 | Firestore subcollection rules | ✅ Deployed | `firestore.rules` |
| F2 | Storage per-user isolation rules | ✅ Deployed | `storage.rules` |
| F3 | App Check `playIntegrity` in release | ✅ Done | `lib/main.dart:69` |
| F4 | Stripe `success_url` / `cancel_url` real URLs | ✅ Done | `functions/index.js` → `https://weldqai.com` |
| F5 | `hasAccess` server-only (not written from client) | ✅ Done | `subscription_service.dart` |
| F6 | **Deploy Cloud Functions** | ⬜ You do | `firebase deploy --only functions` after any changes |

### Play Store Console (all manual)

| # | Item | Status | Notes |
|---|---|---|---|
| PS1 | **Privacy policy** URL | ⬜ You do | Required — you collect auth data, Firestore data |
| PS2 | **Data Safety form** | ⬜ You do | Declare: Firebase Auth, Firestore, Analytics, FCM, Crashlytics |
| PS3 | **Content rating** questionnaire | ⬜ You do | Play Console → Policy → App Content |
| PS4 | **Store listing** — screenshots, icon, description | ⬜ You do | Min 2 phone screenshots required |
| PS5 | **Target audience** | ⬜ You do | Professional / B2B — declare no children's content |
| PS6 | **App signing** — upload signed AAB | ⬜ You do | `flutter build appbundle --release` then upload |

---

## P0 — Fix Immediately (affects live customers)

### [x] P0.1 — Duplicate `status` map key corrupts report data — Fixed Feb 2026
**File:** `lib/core/repositories/report_repository.dart` — lines 558–561, 589–593, 650–653
**Problem:** Multiple report creation methods build a Dart `Map` literal with `'status'` as
a key twice. Dart silently discards the first value. The report is saved with the wrong
status field, corrupting the audit trail.
**Fix:** Remove the duplicate `'status': 'active'` lines. Keep only `'status': status`.
**Also:** Remove `// ignore_for_file: equal_keys_in_map` from line 2 — this suppression
was hiding the bug. Let the linter enforce it going forward.

### [x] P0.2 — Android App Check uses debug provider in production — Fixed Feb 2026
**File:** `lib/main.dart`
**Problem:** `AndroidProvider.debug` is used unconditionally for App Check. This means any
Android user can call the Firebase API without a valid App Check token, bypassing the
entire abuse-prevention layer.
**Fix:**
```dart
androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
```

### [x] P0.3 — Stripe redirect URLs are placeholder strings — Fixed Feb 2026
**File:** `functions/index.js`
**Problem:** `success_url` and `cancel_url` in both `createCheckoutSession` and
`createSubscription` functions are set to `'https://your-app.com/...'`. After a user
completes payment on Stripe, they cannot be redirected back to the app.
**Fix:** Replaced with `https://weldqai.com/payment-success`, `/payment-cancel`,
and `/account` (billing portal return URL).

---

## P1 — Fix Before Growth (security / reliability)

### [x] P1.1 — Client-side payment bypass — Fixed Feb 2026
**File:** `lib/core/services/subscription_service.dart` — `createMonthlySubscription()`
**Problem:** The method wrote `hasAccess: true` directly to Firestore from the client.
**Fix:** Removed client-side write. Stripe webhook handler in `functions/index.js`
sets `hasAccess: true` on `customer.subscription.created` (server-only).

### [x] P1.2 — SyncService reads wrong Firestore paths — Fixed Feb 2026
**File:** `lib/core/services/sync_service.dart`
**Problem:** Three collection paths were wrong:
- `_syncReports()` — read schema metadata docs instead of `items` subcollections
- `_syncTemplates()` — read from `templates` instead of `custom_schemas`
- `_syncProfile()` — read from `profile/info` subcollection instead of top-level user doc
**Fix:** All three paths corrected to match actual schema in `firestore.rules` / CLAUDE.md.

### [x] P1.3 — Firestore security rules don't cover subcollections — Fixed Feb 2026
**File:** `firestore.rules`
**Problem:** Rules covered `/users/{uid}` top-level only. All subcollections unprotected.
**Fix:** Rewrote rules to cover all subcollections. Deployed.

### [x] P1.4 — Storage rules give all authenticated users cross-user file access — Fixed Feb 2026
**File:** `storage.rules`
**Problem:** Catch-all `allow read, write: if request.auth != null` — no user isolation.
**Fix:** Per-user scoped rules with `firestore.get()` collaborator check. Deployed.

### [ ] P1.5 — iOS bundle ID is a placeholder
**File:** `lib/firebase_options.dart`, `ios/Runner/Info.plist`
**Problem:** `iosBundleId: 'com.example.weldqaiApp'` — Flutter default placeholder.
**Fix:** Update to real bundle ID registered in Firebase Console + App Store Connect.
Run `flutterfire configure` to regenerate. Requires Apple Developer account.

### [x] P1.6 — WorkspaceProvider force-unwraps currentUser — Fixed Feb 2026
**File:** `lib/core/providers/workspace_provider.dart`
**Problem:** `FirebaseAuth.instance.currentUser!.uid` crashes on auth state transitions.
**Fix:** Null-checked with `?.uid` guard.

---

## P2 — Architecture Improvements

### [ ] P2.1 — Migrate Provider to Riverpod
**Current:** Single `WorkspaceProvider` `ChangeNotifier` via `provider` package.
**Problem:** No scoped state, no built-in error/loading states, manual stream management.
**Fix:** Migrate to `flutter_riverpod`. Start with subscription status stream.

### [ ] P2.2 — Split DynamicReportForm God Widget
**File:** `lib/features/reports/base/dynamic_report_form.dart` (~1,426 lines)
**Problem:** Single widget handles schema parsing, 8 field types, row tables, validation,
Firestore save, rollup stats, PDF/Excel export, branding, photo, signature, OCR, formula.
**Fix:** Extract into: `ReportFormHeader`, `ReportEntryTable`, `ReportActionBar`,
`ReportPhotoSection`, `ReportSignatureSection`. Use Riverpod for form state.

### [x] P2.3 — Consolidate duplicate Paths class — Fixed Feb 2026
**Files:** `lib/app/router.dart` and `lib/app/constants/paths.dart`
**Fix:** All route constants moved to `constants/paths.dart` (single source of truth).

### [x] P2.4 — Add Firestore emulator test suite — Fixed Feb 2026
Unit tests added for `report_repository`, `subscription_service`, `formula_engine`,
`sync_service` (regression for P1.2). Widget test for `auth_screen`.

### [x] P2.5 — Remove debug print() from active files — Fixed Feb 2026
All `print()` / `debugPrint()` replaced with `AppLogger.*()`. Backed by Sentry in release.

### [x] P2.6 — Add subscription status caching — Fixed Feb 2026
**File:** `lib/core/providers/workspace_provider.dart`, `lib/main.dart`
`WorkspaceProvider` now holds `SubscriptionStatus?` cache backed by `watchStatus()` stream.
`startListening()` called from `AuthGate` on sign-in.

### [x] P2.7 — 15× use_build_context_synchronously warnings — Fixed Feb 2026
All BuildContext-across-async-gap warnings resolved across 9 files. `flutter analyze
--fatal-warnings` returns 0 issues. CI pipeline now green end-to-end.

---

## P3 — Enterprise Features

### [ ] P3.1 — Move subscription enforcement to Cloud Functions
Add server-side middleware check in `functions/index.js` per Cloud Function call.

### [ ] P3.2 — Wire offline UI
Archived screens in `archive/offline_ui/`:
- `offline_mode_screen.dart`
- `widgets/offline_badge.dart`
- `widgets/sync_banner.dart`

Move to `lib/features/offline/`, wire into dashboard using `connectivity_plus`.

### [ ] P3.3 — Organisation-level multi-tenancy
Add `/organisations/{orgId}/` collection with member subcollections and shared
report + schema storage.

### [ ] P3.4 — REST API for external integrations
REST API via Cloud Functions. Auth via Firebase service accounts or API keys.

### [ ] P3.5 — SSO / SAML support
Firebase Auth supports SAML 2.0 and OIDC providers. Configure per-organisation.

---

## CI / CD

| Item | Status |
|---|---|
| GitHub Actions pipeline | ✅ Green |
| Flutter version pinned to `3.32.8` | ✅ |
| Secrets: `FIREBASE_OPTIONS_DART`, `GOOGLE_SERVICES_JSON`, `FIREBASE_WEB_CONFIG_JS` | ✅ Set |
| `firebase_options.dart` excluded from analysis | ✅ |
| `web/firebase-config.js` gitignored, loaded via `<script src>` | ✅ |
| APK artifact uploaded on each CI run | ✅ |

---

## Test Coverage

| File | Type | Covers |
|---|---|---|
| `test/unit/services/formula_engine_test.dart` | Unit | Arithmetic, field refs, conditionals, circular-dep detection |
| `test/unit/services/subscription_service_test.dart` | Unit (FakeFirestore) | `getStatus()`, `canCreateReport()`, `watchStatus()` stream |
| `test/unit/services/sync_service_test.dart` | Unit | P1.2 regression — wrong-path bug |
| `test/unit/repositories/report_repository_test.dart` | Unit (FakeFirestore) | `saveReport()` CRUD, path correctness |
| `test/widget/auth_screen_test.dart` | Widget | Form rendering, validation |

**Coverage gaps:** `dynamic_report_form.dart` (blocked until split), `export_service.dart`
(needs golden tests), `payment_service.dart` (needs Stripe test mode), E2E flow.

---

## How to Use This File

- Change `[ ]` to `[x]` when an item is done; add the date.
- Add new items as they are discovered.
- Items in the **Play Store Launch Checklist** section are the gate for submission.
