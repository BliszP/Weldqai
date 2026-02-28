import 'package:flutter/material.dart';

/// Design token system for WeldQAi — Industrial Inspection Platform.
///
/// Five semantic layers — use the right token for the right purpose:
///   Layer 1 — Foundation: structural chrome (nav bars, scaffolds)
///   Layer 2 — Template category chips (discipline identity)
///   Layer 3 — Semantic status (fixed — never borrowed for anything else)
///   Layer 4 — Feature area accents (AI, NCR, audit, chat)
///   Layer 5 — Form field WPS range feedback
///
/// RULE: [kAmber] does NOT appear inside the running app.
/// Amber is only for: splash screen, app bar logo, PDF headers, marketing.
abstract final class AppTokens {
  // ── Platform amber (external / marketing only) ───────────────────────────
  static const Color kAmber = Color(0xFFD97706);

  // ── Layer 1 — Foundation ─────────────────────────────────────────────────
  static const Color navyDeep     = Color(0xFF0D1B2A); // app bar, nav bar
  static const Color navyPrimary  = Color(0xFF1B3A5C); // section headers, primary buttons
  static const Color surfaceWhite = Color(0xFFFFFFFF); // card / form backgrounds (light)
  static const Color surfaceOff   = Color(0xFFF9FAFB); // screen scaffold (light)

  // Dark-mode equivalents
  static const Color surfaceDark     = Color(0xFF111318); // scaffold dark
  static const Color cardDark        = Color(0xFF1E2125); // card dark
  static const Color borderDark      = Color(0xFF2D3135); // card border dark
  static const Color inputFillDark   = Color(0xFF2A2D31); // input dark
  static const Color dividerDark     = Color(0xFF3D4145);

  // ── Layer 2 — Template category chips ───────────────────────────────────
  // Discipline identity — NOT product sub-brands.
  static const Color catWelding    = Color(0xFF1D4ED8); // steel blue
  static const Color catNdt        = Color(0xFF0F766E); // deep teal
  static const Color catCoating    = Color(0xFF334155); // slate
  static const Color catPressure   = Color(0xFF4338CA); // deep indigo
  static const Color catStructural = Color(0xFF166534); // forest green

  // ── Layer 3 — Semantic status (fixed — never borrowed for other uses) ────
  static const Color statusPass    = Color(0xFF16A34A);
  static const Color statusFail    = Color(0xFFDC2626);
  static const Color statusRepair  = Color(0xFFEA580C);
  static const Color statusPending = Color(0xFF6B7280);
  static const Color statusLocked  = Color(0xFF1F2937);

  // ── Layer 4 — Feature area accents ──────────────────────────────────────
  static const Color featureAi    = Color(0xFF6D28D9); // AI features only
  static const Color featureNcr   = Color(0xFFB45309); // NCR workflow only
  static const Color featureAudit = Color(0xFF374151); // audit / locked state
  static const Color featureChat  = Color(0xFF0369A1); // chat / team

  // ── Layer 5 — Form field WPS range feedback ──────────────────────────────
  /// Value approaches but has not exceeded the WPS limit.
  static const Color wpsNearLimitBorder = Color(0xFFFCD34D);
  static const Color wpsNearLimitLabel  = Color(0xFF92400E);

  /// Value is outside the WPS range entirely.
  static const Color wpsOutOfRangeBorder = Color(0xFFFCA5A5);
  static const Color wpsOutOfRangeLabel  = Color(0xFF991B1B);

  // ── Convenience helpers ──────────────────────────────────────────────────

  /// Returns the Layer 3 status colour for a given status string.
  static Color statusColor(String? status) {
    switch (status) {
      case 'pass':
      case 'accepted':
        return statusPass;
      case 'fail':
      case 'rejected':
        return statusFail;
      case 'repair':
        return statusRepair;
      case 'locked':
      case 'submitted':
        return statusLocked;
      default:
        return statusPending;
    }
  }

  /// Returns the Layer 2 category colour for a given template type string.
  static Color categoryColor(String? type) {
    switch (type) {
      case 'welding':    return catWelding;
      case 'ndt':        return catNdt;
      case 'coating':    return catCoating;
      case 'pressure':   return catPressure;
      case 'structural': return catStructural;
      default:           return catWelding;
    }
  }

  /// Light background tint (10% opacity) for a status badge.
  static Color statusBg(String? status) =>
      statusColor(status).withValues(alpha: 0.10);

  /// Light background tint for a category chip.
  static Color categoryBg(String? type) =>
      categoryColor(type).withValues(alpha: 0.12);
}
