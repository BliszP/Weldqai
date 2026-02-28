# CLAUDE.md — WeldQAi Development Guide

Read this file fully before making any changes.
Last updated: February 2026

---

## 1. Product Identity

**Product name: WeldQAi — Industrial Inspection Platform**

One name. One product. No sub-brands.

WeldQAi handles welding, NDT, coating, pressure testing, structural, and any
inspection type through template categories — not through separate product names.

**Never say or write:**
- FieldSpec, FieldSpec Platform
- CoatQAi, CoatQA, StructQAi, StructQA, PressureQAi, PressureQA, InstQAi

**Always say:**
- WeldQAi (product name)
- Template categories for discipline: welding, NDT, coating, pressure, structural
- "Industrial Inspection Platform" as the one-line descriptor

No paying customers yet. This is a pre-revenue product being built to enterprise standard.

---

## 2. Stack

**Flutter:** SDK ^3.8.1, Material 3, Flutter 3.32.8 pinned in CI
**Firebase:** Firestore, Auth, Storage, Functions (Gen2), App Check, Analytics, FCM, Performance
**Payments:** Stripe via Cloud Functions
**State:** WorkspaceProvider (ChangeNotifier) + subscriptionStatusProvider (Riverpod StreamProvider)
**Navigation:** go_router via `lib/app/router.dart` + `lib/app/constants/paths.dart`

**Does NOT exist yet (do not describe as existing):**
- Node.js REST API
- PostgreSQL
- Claude Vision AI template parser
- `/organisations/{orgId}/` Firestore collections
- NCR screens, weld map screen, branding management screen

---

## 3. Critical Rules

### Never Touch Without Explicit Instruction
- `lib/firebase_options.dart` — do not regenerate without FlutterFire CLI
- `functions/index.js` — production Stripe webhook; changes require testing
- `firestore.rules` / `storage.rules` — every change must be audited
- `android/app/build.gradle.kts` — already fixed (ndkVersion 27, minSdk 23, desugaring)

### Active State (February 2026 — all P0/P1 fixed)
All critical bugs listed in the original CLAUDE.md are fixed:
- Duplicate `status` map key in `report_repository.dart` — FIXED
- `AndroidProvider.debug` in App Check — FIXED (now kDebugMode gated)
- Client-side `hasAccess: true` write — FIXED (server-only via webhook)
- Firestore subcollection rules — FIXED and deployed
- Storage per-user isolation rules — FIXED and deployed
- SyncService wrong paths — FIXED
- 15× `use_build_context_synchronously` warnings — FIXED
- Git history: Firebase web API key purged — FIXED

### Do Not Add Code Back to the God Widget
`dynamic_report_form.dart` was split from 1,429 → 956 lines (P2.2).
Three widgets extracted to `lib/features/reports/widgets/`:
- `report_action_bar.dart` (128 lines) — toolbar
- `report_details_grid.dart` (298 lines) — header fields
- `report_entry_table.dart` (322 lines) — data-entry table

**Do not add code back to `dynamic_report_form.dart`. Split further if needed.**

### Never Do
- Add new global singletons
- Create hardcoded report form files — use schema-driven approach
- Add `// ignore_for_file: equal_keys_in_map` to any file
- Call `FirebaseFirestore.instance.settings` more than once
- Write `hasAccess: true` from client — server only, blocked at rules level
- Use `AndroidProvider.debug` in production
- Use `print()` or `debugPrint()` — use AppLogger

---

## 4. Architecture

### Entry Point
`lib/main.dart` → `lib/app/router.dart` → feature screens

### Data Flow
```
UI Widget
  → Repository (lib/core/repositories/)
    → FirebaseFirestore.instance (direct — no abstraction layer)
      → Cloud Functions (via lib/core/services/payment_service.dart)
```
No Firestore service abstraction layer. `firestore_service.dart` and `auth_service.dart`
were stubs — deleted.

### Report System (Core Feature)
Schema-driven dynamic forms:
1. Schema JSON from `assets/schemas/` or `users/{uid}/custom_schemas/` in Firestore
2. `dynamic_report_form.dart` renders schema (956 lines post-split)
3. Save: `report_repository.dart` writes to Firestore with delta rollups via FieldValue.increment
4. Export: `export_service.dart` generates PDF or Excel, fetches logo from Storage `/branding/logo.png`

### Template Upload Pipeline (Current — Heuristic Only, No AI)
```
template_upload_button.dart (FilePicker: xlsx/xls/pdf)
  → enhanced_template_parser.dart (heuristic extraction — not AI)
    → field_mapping_screen.dart (3-step wizard: Review → Configure → Save)
      → template_manager.dart (saves to SharedPreferences + Firestore custom_schemas)
        → Navigates to /qc_report with new schemaId
```

### Project Workflow
```
project_dashboard_screen.dart (4-tab nav: Home | Projects | KPIs | Team)
  → projects_list_screen.dart (filter: Open/Closed/All, client-side)
    → project_detail_screen.dart (info card, Start Inspection, quick stats)
      → report_catalog_screen.dart → dynamic_report_form.dart
        → report_repository.saveReport() → ProjectRepository.incrementReportCount()
```

---

## 5. File Inventory (48 Active Files)

### Entry & Config
| File | Purpose |
|------|---------|
| `lib/main.dart` | Entry, Firebase init, App Check (kDebugMode gated), ProviderScope, router |
| `lib/firebase_options.dart` | FlutterFire CLI generated — do not hand-edit |
| `lib/app/router.dart` | Named route definitions |
| `lib/app/app_theme.dart` | Material 3 ThemeData — **to be replaced by design token system** |
| `lib/app/constants/paths.dart` | Route name constants — single source of truth |

### State
| File | Purpose |
|------|---------|
| `lib/core/providers/workspace_provider.dart` | ChangeNotifier. User + project state. Null-checked. |
| `lib/core/providers/subscription_providers.dart` | Riverpod StreamProvider. Replaces 3 duplicate Firestore listeners. |

### Models
| File | Purpose |
|------|---------|
| `lib/core/models/chat_message.dart` | Chat message DTO |
| `lib/core/models/template_mapping.dart` | TemplateMapping, FieldMapping, TableMapping, ColumnMapping |

### Repositories
| File | Purpose |
|------|---------|
| `lib/core/repositories/report_repository.dart` | Primary report CRUD. FieldValue.increment for stats. |
| `lib/core/repositories/project_repository.dart` | /users/{uid}/projects/{projectId}. incrementReportCount() atomic. |
| `lib/core/repositories/user_data_repository.dart` | User profile, KPI streams, sharing/collaboration |
| `lib/core/repositories/metrics_repository.dart` | KPI chart reads from /users/{uid}/stats/summary |
| `lib/core/repositories/chat_repository.dart` | Chat messages, attachments, typing indicators |

### Services
| File | Status | Purpose |
|------|--------|---------|
| `lib/core/services/analytics_service.dart` | ✅ | Firebase Analytics + Performance traces |
| `lib/core/services/error_service.dart` | ✅ | Sentry exception capture |
| `lib/core/services/logger_service.dart` | ✅ | AppLogger — levelled logging |
| `lib/core/services/notification_service.dart` | ✅ | FCM handler (foreground + background) |
| `lib/core/services/push_service.dart` | ✅ | Device FCM token → Firestore |
| `lib/core/services/sync_service.dart` | ✅ | Offline sync. Paths fixed Feb 2026. |
| `lib/core/services/subscription_service.dart` | ✅ | Status checks. Client hasAccess write removed. |
| `lib/core/services/pricing_service.dart` | ⚠️ NEEDS UPDATE | Hardcoded fallback: $3/$14/$50 → update to $29/$79/$199 |
| `lib/core/services/payment_service.dart` | ✅ | Stripe checkout via Cloud Functions |
| `lib/core/services/scan_service.dart` | ✅ | ML Kit OCR. Three modes: QR joint tag / OCR field capture / barcode material |
| `lib/core/services/formula_engine.dart` | ✅ | Pure Dart formula evaluator |
| `lib/core/services/export_service.dart` | ✅ | PDF + Excel. Fetches /branding/logo.png from Storage. |
| `lib/core/services/enhanced_template_parser.dart` | ✅ | Heuristic Excel/PDF extraction. No AI. |
| `lib/core/services/template_manager.dart` | ✅ | SharedPreferences (personal) + Firestore custom_schemas |
| `lib/core/services/theme_controller.dart` | ✅ | Dark/light preference via SharedPreferences (device-local) |

### Feature Screens
| File | Purpose |
|------|---------|
| `lib/features/welcome/welcome_screen.dart` | Landing. Hero → How It Works → CTA. |
| `lib/features/auth/auth_screen.dart` | Email/Google login + registration |
| `lib/features/account/account_settings_screen.dart` | Settings, theme toggle, sync status |
| `lib/features/account/complete_profile_screen.dart` | Post-registration. **Add cert fields: certNumber, certBody, certExpiry** |
| `lib/features/account/widgets/upgrade_options_dialog.dart` | Subscription tier + Stripe checkout |
| `lib/features/projects/project_dashboard_screen.dart` | Main hub. 4-tab nav: Home/Projects/KPIs/Team |
| `lib/features/projects/projects_list_screen.dart` | Projects list. Filter client-side. |
| `lib/features/projects/project_detail_screen.dart` | Project hub: info, Start Inspection, stats |
| `lib/features/projects/create_project_screen.dart` | Create / edit project |
| `lib/features/reports/base/dynamic_report_screen.dart` | Route wrapper |
| `lib/features/reports/base/dynamic_report_form.dart` | Core form. 956 lines. Do not add to it. |
| `lib/features/reports/base/multi_report_accordion.dart` | All reports: expand/collapse, export |
| `lib/features/reports/base/report_catalog_screen.dart` | Template catalog: built-in + custom |
| `lib/features/reports/widgets/report_action_bar.dart` | Toolbar: scan/save/export/photos/signatures |
| `lib/features/reports/widgets/report_details_grid.dart` | Header fields |
| `lib/features/reports/widgets/report_entry_table.dart` | Data-entry table |
| `lib/features/reports/widgets/template_upload_button.dart` | File pick → parse → map → save |
| `lib/features/reports/widgets/scan_camera_page.dart` | Full-screen scanner |
| `lib/features/sharing/share_access_screen.dart` | Invite users, manage access |
| `lib/features/chat/project_chat_screen.dart` | Real-time project chat |
| `lib/features/notifications/notifications_screen.dart` | Push notification inbox |
| `lib/features/visualization/visualization_home_screen.dart` | Charts home (between KPI tab and KPI screen) |
| `lib/features/visualization/visualization_kpi_screen.dart` | KPI charts with ChartExporter |

### Shared UI
| File | Purpose |
|------|---------|
| `lib/screens/field_mapping_screen.dart` | 3-step template mapping wizard |
| `lib/widgets/photo_manager_modal.dart` | Photo capture → Firebase Storage |
| `lib/widgets/signature_manager_modal.dart` | Signature pad → Firebase Storage |

### Archived — Ready to Wire
| File | Action |
|------|--------|
| `archive/offline_ui/offline_mode_screen.dart` | Move to `lib/features/offline/` |
| `archive/offline_ui/widgets/offline_badge.dart` | Wire to unsynced report cards |
| `archive/offline_ui/widgets/sync_banner.dart` | Wire below app bar in dashboard + form |

---

## 6. Firestore Data Model

```
/users/{uid}
│   displayName, email, company, role, fcmToken, createdAt, lastSeen
│   [ADD: certNumber, certBody, certExpiry]
│
├── /reports/{schemaId}
│   └── /items/{itemId}
│           reportId, schemaId, schemaTitle, status, reportStatus,
│           details{}, entries[], createdAt, updatedAt, projectId, reportNumber
│           [ADD: photos[] at report level]
│           entries[] rows [ADD: photos[] per row for row-level attachment]
│
├── /stats/summary
│       totalReports, passCount, failCount, pendingCount,
│       repairCount, totalWelds, acceptedWelds, rejectedWelds
│       ⚠️ No per-project, no per-type breakdown
│       [ADD: /users/{uid}/projects/{projectId}/stats/{schemaCategory}]
│
├── /subscription
│   ├── /info    hasAccess, plan, stripeCustomerId, stripeSubscriptionId [write: server-only]
│   ├── /trial   owner writable
│   └── /credits owner writable
│
├── /custom_schemas/{schemaId}
│       schemaId, title, schema{}, fileName, createdAt, updatedAt, createdBy
│       [ADD: version, previousVersionId, approvedBy, approvedAt]
│
├── /projects/{projectId}
│       name, clientName, location, type, status,
│       startDate, endDate, reportCount, createdAt, updatedAt
│       [ADD: /projects/{projectId}/stats/{schemaCategory}]
│       [ADD: /projects/{projectId}/ncr/{ncrId}] — future
│       [ADD: /projects/{projectId}/weld_map/{jointId}] — future
│
└── /notifications/{notifId}
        title, body, read, createdAt, type

/pricing/{region}
    ⚠️ NEEDS REWRITE: currently {one_report, five_reports, monthly}
    REWRITE TO: {field, team, enterprise} with new Stripe price IDs

/materials/{id}
    Shared reference catalog — admin write only, authenticated read
```

**Critical limitation:** All data lives under `/users/{uid}/`. Enterprise multi-user requires
`/organisations/{orgId}/` collections — Phase 2 (Enterprise tier build, not yet started).

---

## 7. Security Rules

### Firestore (`firestore.rules`)

| Collection | Read | Write |
|---|---|---|
| `/materials/{id}` | Any auth user | `isAdmin()` only |
| `/users/{uid}` | Any auth user (sharing lookup) | Owner only |
| `/users/{uid}/subscription/info` | Owner | **`false` — server only** |
| `/users/{uid}/subscription/trial` | Owner | Owner |
| `/users/{uid}/subscription/credits` | Owner | Owner |
| `/users/{uid}/meta/{doc}` | Owner + read collaborator | Owner + write collaborator |
| All other user-scoped | Owner + collaborator by permission | Owner + write collaborator |
| `/users/{uid}/audit_log/{id}` | Owner | create: owner, **update/delete: `false`** |

**`isAdmin()` identity:** `alvespeters@gmail.com`
Hardcoded in both `firestore.rules` and `storage.rules`. Change both if admin account changes.

**Never:**
- Write `hasAccess: true` from client — `subscription/info` write is `false` at rules level
- Give read-only collaborators write access

### Storage (`storage.rules`)

| Path | Read | Write |
|---|---|---|
| `/branding/**` | Public | `isAdmin()` only |
| `/reports/{userId}/**` | Owner | Owner |
| `/users/{userId}/channels/**` | Owner + read collaborator (Firestore check) | Owner |
| `/users/{userId}/**` | Owner | Owner |
| Everything else | `false` | `false` |

### Cloud Functions (`functions/index.js`)

- Never log Stripe secret key material — even a prefix in GCP logs is a credential leak
- Validate `payment_status === 'paid'` before granting access (already done)
- Future: whitelist `priceId` values server-side against known Stripe price IDs
- Future: move `subscription/credits` deduction into Cloud Function

### App Check

```dart
// lib/main.dart — must stay this way
androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
```

---

## 8. Logging

**Always use `AppLogger` — never `print()` or `debugPrint()`.**

```dart
import 'package:weldqai_app/core/services/logger_service.dart';

AppLogger.debug('Sync started for $userId');
AppLogger.info('✅ Report saved — $count items');
AppLogger.warning('⚠️ No schema found, using default');
AppLogger.error('❌ Sync failed', error: e, stackTrace: st);
AppLogger.fatal('Unrecoverable init failure', error: e);
```

- `debug` — detailed trace, debug builds only
- `info` — noteworthy state changes
- `warning` — unexpected but handled
- `error` — feature impaired; always pass `error:` and `stackTrace:` for Sentry
- `fatal` — app cannot continue; global error handlers only

---

## 9. Error Tracking

```dart
import 'package:weldqai_app/core/services/error_service.dart';

try {
  await riskyOperation();
} catch (e, st) {
  AppLogger.error('❌ Operation failed', error: e, stackTrace: st);
  await ErrorService.captureException(e, stackTrace: st, context: 'OperationName');
  rethrow;
}
```

---

## 10. Known Issues Requiring Action

| Priority | Issue | File | Fix |
|----------|-------|------|-----|
| **IMMEDIATE** | `ndtKpisStream()` missing composite Firestore index. NDT KPIs broken. | `user_data_repository.dart`, `firestore.indexes.json` | Add index to `firestore.indexes.json`. Run `firebase deploy --only firestore:indexes` |
| **BEFORE LAUNCH** | `pricing_service.dart` hardcoded fallback: $3/$14/$50 (old model) | `lib/core/services/pricing_service.dart` | Update to field/$29, team/$79, enterprise/contact |
| **BEFORE LAUNCH** | `/pricing/{region}` Firestore doc has wrong structure | Firestore console | Rewrite to `{field, team, enterprise}` |
| **BEFORE LAUNCH** | Android applicationId: `com.example.weldqai_app` | `android/app/build.gradle.kts` | Change to real ID before Play Store |
| **BEFORE LAUNCH** | iOS bundle ID: `com.example.weldqaiApp` | `firebase_options.dart`, `ios/Runner/Info.plist` | Needs Apple Developer + flutterfire configure |
| **BEFORE LAUNCH** | Firebase web API key — rotate in console | Firebase Console | Project Settings → General → Web API Key → Regenerate |
| **P3.1** | Server-side subscription enforcement missing | `functions/index.js` | Add per-function middleware hasAccess check |
| **P3.2** | Offline UI not wired | `archive/offline_ui/` | Move to `lib/features/offline/`, wire with `connectivity_plus` |

---

## 11. Pricing (No Existing Customers — Clean Slate)

| Tier | Price | Users | Key Gated Features |
|------|-------|-------|--------------------|
| Free Trial | $0 — 14 days | 1 | All features. 5 report limit. PDF watermark. |
| Field | $29/month | 1 | Unlimited reports, projects, export, scan, offline, 3 AI parses/month |
| Team | $79/month/user (min 3) | 3–25 | + Unlimited AI parsing, org library, NCR, weld map, branding |
| Enterprise | $199+/month/user annual | 25+ | + SSO, REST API, audit log export, dedicated support, SLA |

---

## 12. Template Type Taxonomy

Eight types drive how the form engine renders, what the AI parser produces,
and which dashboard metrics auto-generate.

| Type | Structure | Examples |
|------|-----------|---------|
| `HEADER_ONLY` | Details only, no table | Pre-weld setup |
| `HEADER_TABLE` | Details + one repeating table | VT inspection, fit-up, DFT |
| `HEADER_MULTI_TABLE` | Details + 2–4 distinct tables | WPS parameter log |
| `CHECKLIST` | Yes/No/NA items | Pre-weld checklist |
| `TIME_SERIES` | Timestamped readings | Hydrotest, PWHT |
| `RELATIONAL` | References a prior report (mandatory parent) | NDT (references VT) |
| `CORRECTIVE` | Lifecycle: Open → In Progress → Closed | NCR |
| `REGISTER` | Aggregates child reports | Weld map / joint register |

---

## 13. Colour System

Full spec: `FieldSpec_Colour_System.docx`

**Critical rule:** Platform amber (#D97706) does NOT appear inside the running app.
Amber is used only on: splash screen, app bar logo, PDF headers, marketing.

Inside the app, every colour comes from these layers:

**Layer 1 — Foundation (frame, no meaning)**
- `navyDeep` #0D1B2A — app bar, nav bar
- `navyPrimary` #1B3A5C — section headers, primary buttons, card headers
- `surfaceWhite` #FFFFFF — card/form backgrounds
- `surfaceOff` #F9FAFB — screen scaffold

**Layer 2 — Template Category Chips**
(discipline identity — not product sub-brands)
- Welding: #1D4ED8 steel blue
- NDT: #0F766E deep teal
- Coating: #334155 slate
- Pressure: #4338CA deep indigo
- Structural: #166534 forest green

**Layer 3 — Semantic Status (fixed, never borrowed for anything else)**
- Pass: #16A34A | Fail: #DC2626 | Repair: #EA580C | Pending: #6B7280 | Locked: #1F2937

**Layer 4 — Feature Areas**
- AI features only: #6D28D9 violet
- NCR workflow only: #B45309 dark amber
- Audit/locked state: #374151 charcoal
- Chat/team: #0369A1 sky blue

**Layer 5 — Form Information (supports inspector judgement — never blocks)**
- Near WPS limit: border #FCD34D, label #92400E
- Outside WPS range: border #FCA5A5, label #991B1B
- After inspector moves to next field: returns to normal, no acknowledgement required

---

## 14. Scan Feature Behaviour

`scan_service.dart` (ML Kit) + `scan_camera_page.dart`. Three modes by context:

| Context | Mode | Result |
|---------|------|--------|
| No field focused, tap scan | QR — Joint Tag | Parses joint number, drawing ref, welder ID from QR. Auto-populates matching fields. |
| Text/number field focused, tap scan | OCR — Field Capture | Reads value from camera into the focused field. Inspector accepts or rejects. |
| Material/heat number field focused | Barcode — Material Cert | Reads barcode, populates heat number. Links to /materials/ if match found. |

---

## 15. Photo & Signature Attachment

**Photos — two levels:**
- Report-level: via ReportActionBar → `photo_manager_modal.dart` → Storage `/users/{uid}/reports/{reportId}/photos/report_{n}.jpg` → PDF gallery at end of report
- Row-level: via row camera icon in `report_entry_table.dart` → Storage `/users/{uid}/reports/{reportId}/photos/row_{rowIndex}_{n}.jpg` → PDF inline at that row

**Signatures — placement by template type:**
- Most types: end of form only, inspector sign-off
- PWHT (TIME_SERIES): mid-form at each hold point + final sign-off
- NCR (CORRECTIVE): three sign-offs — raiser, disposition approver, closure authority

**Branding logo:**
- Uploaded by admin via `branding_management_screen.dart` (to be built)
- Stored at Storage path: `/branding/logo.png`
- `export_service.dart` already reads this path — backend ready, UI screen missing

---

## 16. Enterprise Upgrade Sequence

Build in this order. Each item states what existing code it touches.

| Week | Task | Existing Files Touched | New Files Created |
|------|------|----------------------|-------------------|
| 1 — Day 1 | Fix NDT composite index | `firestore.indexes.json` | — |
| 1 — Day 1–2 | Design token system | `lib/app/app_theme.dart` (delete after) | `lib/core/design/app_tokens.dart`, `lib/core/design/app_theme.dart` |
| 1 — Day 3 | CWI cert on profile + PDF | `complete_profile_screen.dart`, `export_service.dart`, Firestore user profile | — |
| 1 — Day 4 | Report lock after submission | `dynamic_report_form.dart`, `report_repository.dart`, `firestore.rules` | — |
| 1 — Day 5 | Audit log service | `report_repository.dart`, `firestore.rules` | `lib/core/services/audit_log_service.dart` |
| 2 | Wire offline UI | `project_dashboard_screen.dart`, `dynamic_report_form.dart`, `pubspec.yaml` | Move `archive/offline_ui/` → `lib/features/offline/` |
| 2 | Branding management screen | `lib/app/constants/paths.dart`, `lib/app/router.dart` | `lib/features/account/branding_management_screen.dart`, `lib/app/constants/roles.dart` |
| 2–3 | Per-project per-type stats | `report_repository.dart`, `metrics_repository.dart` | New Firestore path `/projects/{id}/stats/{cat}` |
| 3 | Template versioning | `template_manager.dart`, `report_catalog_screen.dart` | Version fields in `custom_schemas` Firestore docs |
| 3 | Pricing update | `pricing_service.dart`, `upgrade_options_dialog.dart`, `functions/index.js` | Rewrite `/pricing/{region}` Firestore doc |
| 4–5 | Row-level photo attachment | `report_entry_table.dart`, `photo_manager_modal.dart`, `export_service.dart` | — |
| 5–6 | Node.js API + AI template parser | `template_upload_button.dart`, `field_mapping_screen.dart` (Step 3 replaced) | `api/` directory, `lib/features/reports/ai_confirmation_screen.dart` |
| 6–7 | NCR workflow | `report_repository.dart`, `project_detail_screen.dart` | `lib/features/ncr/ncr_tracker_screen.dart`, `lib/features/ncr/ncr_detail_screen.dart` |
| 7–8 | Weld map screen | `project_detail_screen.dart` | `lib/features/projects/weld_map_screen.dart` |
| 8+ | Organisation hierarchy | `share_access_screen.dart`, `template_manager.dart` | `lib/features/org/`, `/organisations/{orgId}/` Firestore collections |

---

## 17. Build Commands

```bash
flutter pub get
flutter analyze --fatal-warnings    # Must be 0 issues
flutter build apk --debug
flutter build apk --release         # Requires signing config
flutter build appbundle --release   # For Play Store submission

# Firebase
firebase deploy --only firestore:rules
firebase deploy --only storage
firebase deploy --only functions
firebase deploy --only firestore:indexes    # Fix NDT KPI bug

# Tests
flutter test
flutter test --coverage
```

---

## 18. Test Coverage

| File | Type | Covers |
|------|------|--------|
| `test/unit/services/formula_engine_test.dart` | Unit | Arithmetic, field refs, conditionals, circular-dep |
| `test/unit/services/subscription_service_test.dart` | Unit (FakeFirestore) | getStatus(), canCreateReport(), watchStatus() |
| `test/unit/services/sync_service_test.dart` | Unit | P1.2 path regression |
| `test/unit/repositories/report_repository_test.dart` | Unit (FakeFirestore) | saveReport() CRUD, path correctness |
| `test/widget/auth_screen_test.dart` | Widget | Form render, validation |

**Gaps:** `export_service.dart` (golden tests needed), `payment_service.dart` (Stripe test mode), `ReportDetailsGrid`/`ReportEntryTable` (now unblocked after P2.2 split), E2E flow.

---

## 19. Play Store Remaining Blockers

| # | Item | Status |
|---|------|--------|
| B3 | Generate upload keystore | ⬜ You do |
| B4 | Create `android/key.properties` | ⬜ You do |
| B5 | Change applicationId from `com.example.weldqai_app` | ⬜ You do |
| B6 | Register new package in Firebase Console | ⬜ You do |
| B7 | Update GOOGLE_SERVICES_JSON GitHub Secret | ⬜ You do |
| B8 | iOS bundle ID — needs Apple Developer + flutterfire configure | ⬜ You do |
| PS1 | Privacy policy URL | ⬜ You do |
| PS2 | Data Safety form | ⬜ You do |
| PS4 | Store listing — screenshots, icon, description | ⬜ You do |
| PS6 | Upload signed AAB to Play Store internal track | ⬜ You do |

---

*WeldQAi — Industrial Inspection Platform*
*One name. Template categories distinguish the discipline. Enterprise standard.*
