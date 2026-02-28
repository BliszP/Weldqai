// ignore_for_file: deprecated_member_use, unnecessary_cast

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:weldqai_app/app/constants/paths.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Remove AppBar so the top bar flows into the hero as one seamless block
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top bar + Hero — unified dark navy block
            const _HeroSection(),

            // 2. How It Works — white / near-white
            _HowItWorksSection(isDark: isDark),

            // 3. Final CTA — dark navy (bookend with hero)
            _FinalCTA(isDark: isDark),
          ],
        ),
      ),
      bottomNavigationBar: const _Footer(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Colour constants
// ─────────────────────────────────────────────────────────────────────────────
const _kHeroBg = Color(0xFF0D1F2D); // deep navy
const _kAmber  = Color(0xFFF59E0B); // industrial amber

/* ══════════════════════════════════════════════════════════════════════════════
   HERO — full-bleed dark navy panel
══════════════════════════════════════════════════════════════════════════════ */

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 640;
    final topPad  = MediaQuery.of(context).padding.top; // status bar height

    return Container(
      width: double.infinity,
      color: _kHeroBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Inline nav bar (same dark navy — no seam) ──────────────────
          Padding(
            padding: EdgeInsets.only(
              top: topPad + 8,
              left: isPhone ? 20 : 40,
              right: isPhone ? 8 : 16,
              bottom: 8,
            ),
            child: Row(
              children: [
                // Logo
                const Text(
                  'WeldQAi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                // Amber dot accent
                const SizedBox(width: 4),
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: _kAmber, shape: BoxShape.circle),
                ),
                const Spacer(),
                // Nav links or overflow menu
                if (isPhone)
                  _HeroMoreMenu()
                else ...[
                  _HeroNavLink('How it Works', _ContentSheet.howItWorks),
                  _HeroNavLink('FAQ',          _ContentSheet.faq),
                  _HeroNavLink('Why Us?',      _ContentSheet.whyUs),
                  _HeroNavLink('Contact',      _ContentSheet.contact),
                ],
              ],
            ),
          ),

          // ── Hero content ───────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              isPhone ? 24 : 48,
              isPhone ? 28 : 40,
              isPhone ? 24 : 48,
              isPhone ? 28 : 44,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    // Compliance badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 16, color: _kAmber),
                          SizedBox(width: 6),
                          Text(
                            'AWS / ASME / ISO Compliant',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kAmber,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Headline
                    Text(
                      'Welding QA/QC Intelligence',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        color: Colors.white,
                        fontSize: isPhone ? 28 : null,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Subheadline
                    const Text(
                      'Replace scattered spreadsheets with intelligent inspection management. '
                      'Start your first report in 60 seconds.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFB0C4D8),
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // CTAs
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => Navigator.pushNamed(
                            context, Paths.auth,
                            arguments: {'initialMode': 'signup'},
                          ),
                          icon: const Icon(Icons.rocket_launch, size: 18),
                          label: const Text('Get Started Free'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _kAmber,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pushNamed(
                            context, Paths.auth,
                            arguments: {'initialMode': 'login'},
                          ),
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('Sign In'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF4A6F8A)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      '✓ No credit card required  •  ✓ 2-minute setup',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A9BB5)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Amber accent line at foot of hero
          Container(height: 3, color: _kAmber),
        ],
      ),
    );
  }
}

// Inline nav link for the hero bar (white text on dark navy)
class _HeroNavLink extends StatelessWidget {
  const _HeroNavLink(this.text, this.open);
  final String text;
  final void Function(BuildContext) open;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => open(context),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFB0C4D8)),
        child: Text(text),
      );
}

// Overflow menu for phones — white icon on dark navy
class _HeroMoreMenu extends StatelessWidget {
  const _HeroMoreMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuItem>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (item) => item.onTap(context),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _MenuItem('How it Works', _ContentSheet.howItWorks),
          child: const Text('How it Works'),
        ),
        PopupMenuItem(
          value: _MenuItem('FAQ', _ContentSheet.faq),
          child: const Text('FAQ'),
        ),
        PopupMenuItem(
          value: _MenuItem('Why Us?', _ContentSheet.whyUs),
          child: const Text('Why Us?'),
        ),
        PopupMenuItem(
          value: _MenuItem('Contact', _ContentSheet.contact),
          child: const Text('Contact'),
        ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════════
   HOW IT WORKS — 3-step inline section
══════════════════════════════════════════════════════════════════════════════ */

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection({required this.isDark});
  final bool isDark;

  static const _steps = [
    _Step(1, Icons.upload_file,    'Choose Schema',
        'Pick from built-in AWS/ASME/ISO templates or upload your own Excel/PDF form.'),
    _Step(2, Icons.edit_note,      'Inspect & Capture',
        'Fill in field data, scan weld tags, capture signatures and photos on-site.'),
    _Step(3, Icons.picture_as_pdf, 'Export & Share',
        'One-click PDF/Excel reports — branded and client-ready in seconds.'),
  ];

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 640;
    final bg = isDark ? const Color(0xFF1E2125) : Colors.white;

    return Container(
      width: double.infinity,
      color: bg,
      padding: EdgeInsets.fromLTRB(
        isPhone ? 24 : 48,
        32, // reduced from 56 — sits closer to the hero
        isPhone ? 24 : 48,
        56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Text(
                'How It Works',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Three steps from job site to client-ready report',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 28),
              isPhone
                  ? Column(
                      children: _steps
                          .map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: _StepCard(step: s, isDark: isDark),
                              ))
                          .toList(),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < _steps.length; i++) ...[
                          Expanded(child: _StepCard(step: _steps[i], isDark: isDark)),
                          if (i < _steps.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Icon(Icons.arrow_forward,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[300]),
                            ),
                        ],
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step {
  final int    number;
  final IconData icon;
  final String title;
  final String description;
  const _Step(this.number, this.icon, this.title, this.description);
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.isDark});
  final _Step step;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Number badge + icon
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _kAmber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, size: 30, color: _kAmber),
            ),
            Positioned(
              top: 0, right: 0,
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  color: _kAmber, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '${step.number}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Text(step.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
            )),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════════
   FINAL CTA — primary gradient
══════════════════════════════════════════════════════════════════════════════ */

class _FinalCTA extends StatelessWidget {
  const _FinalCTA({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      color: _kHeroBg, // dark navy — bookends the hero at the top
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmall ? 24 : 48,
              vertical: isSmall ? 48 : 72,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    // Section label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kAmber.withValues(alpha: 0.35)),
                      ),
                      child: const Text(
                        'Get Started Today',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kAmber,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Ready to modernize your QA/QC workflow?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isSmall ? 22 : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Join teams who have eliminated paperwork and reduced inspection time by 95%.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFB0C4D8),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context, Paths.auth,
                        arguments: {'initialMode': 'signup'},
                      ),
                      icon: const Icon(Icons.rocket_launch, size: 18),
                      label: Text(isSmall ? 'Start Free' : 'Start Free Today'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAmber,
                        foregroundColor: Colors.black87,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmall ? 24 : 32,
                          vertical: isSmall ? 14 : 16,
                        ),
                        textStyle: TextStyle(
                          fontSize: isSmall ? 15 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Amber top accent line above the footer
          Container(height: 1, color: _kAmber.withValues(alpha: 0.25)),
        ],
      ),
    );
  }
}

// _MenuItem is shared between _HeroMoreMenu (phone nav) and any future menus
class _MenuItem {
  final String label;
  final void Function(BuildContext) onTap;
  _MenuItem(this.label, this.onTap);
}

/* ══════════════════════════════════════════════════════════════════════════════
   FOOTER
══════════════════════════════════════════════════════════════════════════════ */

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          TextButton(onPressed: () => _ContentSheet.about(context),      child: const Text('About')),
          TextButton(onPressed: () => _ContentSheet.terms(context),      child: const Text('Terms')),
          TextButton(onPressed: () => _ContentSheet.privacy(context),    child: const Text('Privacy')),
          TextButton(onPressed: () => _ContentSheet.disclaimer(context), child: const Text('Disclaimer')),
        ],
      ),
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════════
   CONTENT SHEETS (bottom sheets for nav links)
══════════════════════════════════════════════════════════════════════════════ */

class _ContentSheet {
  static Future<void> _open(
    BuildContext context, {
    required String title,
    required List<_Section> sections,
    Widget? customContent,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final screenW    = MediaQuery.of(ctx).size.width;
        final maxWidth   = screenW < 720 ? 560.0 : 720.0;
        final rawScale   = MediaQuery.of(ctx).textScaleFactor;
        final clampedScale = rawScale.clamp(1.0, 1.2) as double;

        final base        = Theme.of(ctx).textTheme;
        final titleStyle  = base.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1);
        final sectionStyle = base.titleMedium?.copyWith(fontWeight: FontWeight.w600);
        final bodyStyle   = base.bodyMedium?.copyWith(height: 1.4);

        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaleFactor: clampedScale),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, controller) => Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: Text(title, style: titleStyle)),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                        ),
                      ]),
                      const SizedBox(height: 4),
                      const Divider(height: 24),
                      Expanded(
                        child: ListView(
                          controller: controller,
                          children: [
                            if (customContent != null)
                              customContent
                            else
                              for (final s in sections) ...[
                                Text(s.title, style: sectionStyle),
                                const SizedBox(height: 4),
                                for (final p in s.paragraphs)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(p, style: bodyStyle),
                                  ),
                                const SizedBox(height: 10),
                              ],
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static void howItWorks(BuildContext c) =>
      _open(c, title: 'How WeldQAi Works', sections: _copyHowItWorks);
  static void faq(BuildContext c) =>
      _open(c, title: 'Frequently Asked Questions', sections: _copyFaq);
  static void whyUs(BuildContext c) =>
      _open(c, title: 'Why WeldQAi', sections: _copyWhyUs);
  static void about(BuildContext c) =>
      _open(c, title: 'About WeldQAi', sections: _copyAbout);
  static void terms(BuildContext c) =>
      _open(c, title: 'Terms of Use', sections: _copyTerms);
  static void privacy(BuildContext c) =>
      _open(c, title: 'Privacy', sections: _copyPrivacy);
  static void disclaimer(BuildContext c) =>
      _open(c, title: 'Disclaimer', sections: _copyDisclaimer);
  static void contact(BuildContext c) =>
      _open(c, title: 'Contact WeldQAi', sections: [],
            customContent: const _ContactInfo());

  static final _copyHowItWorks = [
    _Section('Overview', [
      'WeldQAi streamlines QA/QC for welding and fabrication projects. Choose a standard schema, capture data in real time, validate automatically, and export polished reports.',
    ]),
    _Section('Steps', [
      '1) Select or Upload Schema — Use preloaded AWS/ASME/ISO/NACE templates or bring your own.',
      '2) Capture Details — Enter inspection and welding data on laptop or tablet.',
      '3) Automated Validation — Built-in rules flag missing or inconsistent entries.',
      '4) Live Dashboards — Track progress, repair cycles, rejection ratios, KPIs.',
      '5) One-Click Exports — Generate client-ready PDF/Excel with your branding.',
      '6) Collaboration — Invite team members with role-based access controls.',
    ]),
  ];

  static final _copyFaq = [
    _Section('Who is it for?', [
      'QA/QC inspectors, welding engineers, project managers, fabrication supervisors, and contractors.',
    ]),
    _Section('What standards are supported?', [
      'AWS, ASME, ISO, NACE, and client-specific criteria via custom schemas.',
    ]),
    _Section('Is mobile supported?', [
      'Yes — optimised for phones and tablets. Offline mode available for job sites with poor connectivity.',
    ]),
    _Section('Is data secure?', [
      'Yes. Data is stored in Firebase with encryption at rest and in transit, and access is restricted by roles.',
    ]),
    _Section('How is this better than Excel/PDF?', [
      'Fewer manual errors, standardized outputs, real-time KPIs, and effortless sharing.',
    ]),
  ];

  static final _copyWhyUs = [
    _Section('Built by practitioners', [
      'Designed by people who have lived the welding QA/QC workflow end-to-end.',
    ]),
    _Section('Comprehensive coverage', [
      'Welding operations, NDT, hydrotests, coating, PWHT, welder qualifications — unified in one platform.',
    ]),
    _Section('Future-proof architecture', [
      'Schema-driven design means adding new report types without code rewrites.',
    ]),
    _Section('Insight over paperwork', [
      'Dashboards and KPIs turn data into decisions, reducing rework and delay.',
    ]),
    _Section('Security & compliance', [
      'Cloud-hosted, encrypted, and aligned with international QA/QC standards.',
    ]),
  ];

  static final _copyAbout = [
    _Section('Our mission', [
      'Bring intelligence and efficiency to welding QA/QC by replacing scattered spreadsheets and paper trails with a smart, cloud-based platform.',
    ]),
    _Section('What we value', [
      'Accuracy, speed, and transparency. We build tools that help teams deliver quality on time and with confidence.',
    ]),
  ];

  static final _copyTerms = [
    _Section('Use of Service', [
      'Use WeldQAi for lawful QA/QC and reporting purposes. Do not reverse engineer or misuse the platform.',
    ]),
    _Section('Reports & Compliance', [
      'WeldQAi assists with documentation, but certified professional judgment and regulatory compliance remain the user responsibility.',
    ]),
    _Section('Liability', [
      'The service is provided "as is". WeldQAi is not liable for indirect, incidental, or consequential damages.',
    ]),
    _Section('IP & Content', [
      'All platform IP remains the property of WeldQAi. You retain ownership of data you enter.',
    ]),
  ];

  static final _copyPrivacy = [
    _Section('Data Ownership', [
      'You own the project data you store in WeldQAi. We do not sell your data.',
    ]),
    _Section('Security', [
      'Encryption in transit (TLS) and at rest. Role-based access limits who can view or edit data.',
    ]),
    _Section('Limited Use', [
      'We process data only to provide the service and basic analytics to improve reliability and usability.',
    ]),
    _Section('Your Rights', [
      'You may request data export or deletion of your account and associated data.',
    ]),
  ];

  static final _copyDisclaimer = [
    _Section('Professional Judgment', [
      'WeldQAi is a tool to assist QA/QC. It does not replace certified inspector judgment or applicable codes.',
    ]),
    _Section('Accuracy', [
      'We work to ensure accuracy, but errors or omissions may occur. Always verify critical results.',
    ]),
  ];
}

class _Section {
  final String title;
  final List<String> paragraphs;
  const _Section(this.title, this.paragraphs);
}

/* ══════════════════════════════════════════════════════════════════════════════
   CONTACT INFO
══════════════════════════════════════════════════════════════════════════════ */

class _ContactInfo extends StatelessWidget {
  const _ContactInfo();

  Future<void> _launchEmail(BuildContext context, String email) async {
    final uri = Uri(scheme: 'mailto', path: email, query: 'subject=WeldQAi Inquiry');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open email app. Please email: $email')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Get in touch',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Have questions, feedback, or interested in a pilot program?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600])),
            const SizedBox(height: 24),
            _EmailButton(
              icon: Icons.email,
              label: 'General Inquiries',
              email: 'info@weldqai.com',
              onTap: () => _launchEmail(context, 'info@weldqai.com'),
            ),
            const SizedBox(height: 12),
            _EmailButton(
              icon: Icons.support_agent,
              label: 'Technical Support',
              email: 'support@weldqai.com',
              onTap: () => _launchEmail(context, 'support@weldqai.com'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.schedule, size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'We typically respond within 24 hours during business days.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _EmailButton extends StatelessWidget {
  const _EmailButton({
    required this.icon,
    required this.label,
    required this.email,
    required this.onTap,
  });

  final IconData   icon;
  final String     label;
  final String     email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(email,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16,
                color: isDark ? Colors.grey[600] : Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════════
   CONTACT FORM (kept for reference — not currently linked from nav)
══════════════════════════════════════════════════════════════════════════════ */

class _ContactForm extends StatefulWidget {
  const _ContactForm();

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _name    = TextEditingController();
  final _email   = TextEditingController();
  final _company = TextEditingController();
  final _message = TextEditingController();
  bool _sending  = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _company.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('contact_messages').add({
        'name':      _name.text.trim(),
        'email':     _email.text.trim(),
        'company':   _company.text.trim(),
        'message':   _message.text.trim(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message sent. Thank you!')));
        _formKey.currentState!.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 560;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    final nameEmailFields = [
      Flexible(
        child: TextFormField(
          controller: _name,
          decoration: deco('Name'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ),
      const SizedBox(width: 12, height: 12),
      Flexible(
        child: TextFormField(
          controller: _email,
          decoration: deco('Email'),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            final t  = v?.trim() ?? '';
            final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t);
            return ok ? null : 'Valid email required';
          },
        ),
      ),
    ];

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              isNarrow
                  ? Column(children: nameEmailFields)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: nameEmailFields),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _company, decoration: deco('Company (optional)')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                decoration: deco('Message'),
                maxLines: 6,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter a message'
                    : null,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(_sending ? 'Sending...' : 'Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
