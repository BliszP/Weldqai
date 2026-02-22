# Performance Baseline — 2026-02-21

Measured after codebase reorganisation (release 6) and STEP 6B quick-win
optimisations. Use this document as the comparison point for future
size-reduction work.

---

## APK Size — Baseline

| Metric | Value |
|---|---|
| Build command | `flutter build apk --release --target-platform android-arm64 --analyze-size` |
| Total compressed APK | **87.2 MB** |
| Build date | 2026-02-21 |
| flutter analyze issues | **4** (all `info`, no errors) |

### Size Breakdown by Component

| Component | Size |
|---|---|
| `lib/arm64-v8a` (native .so) | 36 MB |
| `lib/armeabi-v7a` (from bundled AARs) | 9 MB |
| `lib/x86` (from bundled AARs) | 16 MB |
| `lib/x86_64` (from bundled AARs) | 16 MB |
| `assets/flutter_assets` | 3 MB |
| `assets/mlkit-google-ocr-models` | 1 MB |
| `assets/mlkit_barcode_models` | 860 KB |
| `classes.dex` | 3 MB |
| `classes2.dex` | 210 KB |
| `resources.arsc` | 335 KB |

### Dart AOT Symbol Breakdown (decompressed)

| Package | Size |
|---|---|
| `package:flutter` | 4 MB |
| `package:syncfusion_flutter_pdf` | 924 KB |
| `package:weldqai_app` (app code) | **787 KB** |
| `package:image` | 725 KB |
| `dart:core` | 321 KB |
| `package:pdf` | 253 KB |
| `package:fl_chart` | 243 KB |
| `dart:ui` | 219 KB |
| `package:bidi` | 217 KB |
| `dart:typed_data` | 216 KB |
| `package:excel` | 113 KB |
| `package:archive` | 98 KB |
| `package:xml` | 86 KB |
| `package:cloud_firestore_platform_interface` | 70 KB |
| `package:petitparser` | 61 KB |
| `package:firebase_auth_platform_interface` | 58 KB |

---

## Heavy Dependencies — Risk Assessment

| Package | Approx Impact | Notes | Action |
|---|---|---|---|
| `google_mlkit_text_recognition` | ~20 MB native | OCR for template scan feature. Includes Latin model (~1 MB assets) + arm64 binary. Non-Latin models (Chinese/Devanagari/Japanese/Korean) are referenced but NOT bundled — suppressed via `proguard-rules.pro`. | Keep. Required for OCR scan. Consider lazy-load in Phase 2. |
| `syncfusion_flutter_pdf` | ~924 KB Dart | Commercial PDF library. Used for template parsing only. Large binary footprint. | Evaluate replacing with `pdf` package for read+write, removing Syncfusion entirely. Saves ~924 KB Dart + native code. |
| `font_awesome_flutter` | ~14 KB after tree-shaking | Icon font — 99.1% tree-shaken (`1,645,184 → 14,664 bytes`). | No action needed. Tree-shaking handles this. |
| `flutter_html` | Unknown (not in AOT top) | Heavy HTML renderer. Currently unused in visible screens — only imported for potential rich text display. | Audit usages. If only 1–2 call sites, replace with `SelectableText` or `Text.rich`. Potential to remove entirely. |
| `image` (dart) | 725 KB | Image decode/encode library. Pulled in transitively. | Audit if app directly uses it or if it's transitive. |
| `mobile_scanner` | In native binary | Barcode scanner with bundled ML model (~860 KB assets). | Keep. Required for QR/barcode scan. |
| `syncfusion_flutter_pdf` + `excel` | 924 KB + 113 KB | Both used for template upload/parsing. | Keep for now. Revisit in P2 refactor. |

---

## Analyse Issues — Baseline vs After Optimisations

| Metric | Before STEP 6B | After STEP 6B |
|---|---|---|
| Errors | 0 | 0 |
| Warnings | 0 | 0 |
| Info issues | 46 | **4** |
| `avoid_print` | 30+ | 0 ✅ |
| `deprecated_member_use` (withOpacity) | 4+ visible + many suppressed | 0 ✅ |
| `use_super_parameters` | 1 | 0 ✅ |
| `unnecessary_import` | 0 | 0 ✅ |
| `unnecessary_to_list_in_spreads` | 1 | 0 ✅ |
| `avoid_types_as_parameter_names` | 1 | 0 ✅ |
| `deprecated_member_use` (DragTarget) | 0 (suppressed) | 4 (now visible) |

### Remaining 4 Issues

All in `lib/screens/field_mapping_screen.dart`:
- Lines 1076–1077: `onWillAccept` / `onAccept` on `DragTarget` — deprecated in favour of `onWillAcceptWithDetails` / `onAcceptWithDetails` (Flutter 3.14+). Requires logic change to use `DragTargetDetails` wrapper. Deferred to next development cycle.

---

## Anti-Patterns Found

| File | Line(s) | Issue | Status |
|---|---|---|---|
| 15 files | 123 calls | `print()` in production code | ✅ Fixed — replaced with `debugPrint()` |
| `app_theme.dart` | 76 | `withOpacity()` deprecated, file suppress hiding it | ✅ Fixed |
| `upgrade_options_dialog.dart` | 346, 453 | `withOpacity()` deprecated | ✅ Fixed |
| `auth_screen.dart` | 274, 276 | `withOpacity()` deprecated | ✅ Fixed |
| `project_dashboard_screen.dart` | 1344 | `withOpacity()` deprecated | ✅ Fixed |
| `field_mapping_screen.dart` | 10 locations | `withOpacity()` deprecated, hidden by suppress | ✅ Fixed |
| `welcome_screen.dart` | 292, 345, 455, 476 | `withOpacity()` deprecated | ✅ Fixed |
| `scan_camera_page.dart` | 99, 101, 115 | `withOpacity()` deprecated | ✅ Fixed |
| `upgrade_options_dialog.dart` | 25 | `use_super_parameters` — old Key? key syntax | ✅ Fixed |
| `enhanced_template_parser.dart` | 5 | `unnecessary_import` dart:typed_data | ✅ Fixed |
| `field_mapping_screen.dart` | 1447 | `unnecessary_to_list_in_spreads` | ✅ Fixed |
| `photo_manager_modal.dart` | 464 | `avoid_types_as_parameter_names` (sum) | ✅ Fixed |
| `dynamic_report_form.dart` | many | `setState()` on every keystroke rebuilds 1,426-line widget | ⏳ P2.2 — architecture refactor required |
| 4 files | — | Firestore reads inside `build()` methods | ⏳ Move to `initState` or stream-driven |

## Firestore Reads in build() — Detail

Detected Firestore access inside `Widget build()` methods in:
- `lib/features/welcome/welcome_screen.dart`
- `lib/features/sharing/share_access_screen.dart`
- `lib/features/projects/project_dashboard_screen.dart`
- `lib/features/notifications/notifications_screen.dart`

These reads fire on every rebuild (e.g. on device rotation, theme change, parent
setState). Each should be moved to `initState()`, a `FutureBuilder`, or a
`StreamBuilder`. Defer to the Riverpod migration (P2.1).

---

## Target After Optimisation

| Metric | Current | Target |
|---|---|---|
| APK size (arm64 only) | 87.2 MB | < 60 MB |
| Analyse issues | 4 info | 0 |
| Dart AOT — app code | 787 KB | < 700 KB |

### Recommended Size Reduction Steps (Phase 2)

1. **Remove `syncfusion_flutter_pdf`** (~924 KB Dart + native overhead) — use `pdf` package for all read operations, which is already a dependency. Saves ~5–10 MB.
2. **Lazy-load `google_mlkit_text_recognition`** — only initialise OCR when the scan screen is opened. Reduces startup cost; does not reduce APK size.
3. **Audit `flutter_html`** — if < 3 usages, replace with `Text.rich`. Potential to remove the package and save ~2–5 MB.
4. **Remove `flutter_web_plugins` from pubspec if web is not a shipping target** — confirms whether web bundle size is counted.
5. **Add `--split-per-abi` to release build** — produces per-ABI APKs (~30 MB arm64-only). The 87 MB figure includes multiple ABIs bundled together.
