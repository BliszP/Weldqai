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
      appBar: const _TopBar(),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  
                  // Hero Section
                  _HeroSection(isDark: isDark),
                  
                  const SizedBox(height: 48),
                  
                  // Feature Cards
                  const _FeatureGrid(),
                  
                  const SizedBox(height: 48),
                  
                  // Social Proof
                  _SocialProofSection(isDark: isDark),
                  
                  const SizedBox(height: 48),
                  
                  // Final CTA
                  _FinalCTA(isDark: isDark),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _Footer(),
    );
  }
}

/* ------------------------------- HERO SECTION ------------------------------ */

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'AWS/ASME/ISO Compliant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Main Headline
        Text(
          'Welding QA/QC Intelligence',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Subheadline
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Text(
            'Replace scattered spreadsheets with intelligent inspection management. Start your first report in 60 seconds.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.grey[300] : Colors.grey[700],
              height: 1.5,
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Primary CTAs
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context, 
                  Paths.auth,
                  arguments: {'initialMode': 'signup'},
                );
              },
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Get Started Free'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context, 
                  Paths.auth,
                  arguments: {'initialMode': 'login'},
                );
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Trust Indicator
        Text(
          '✓ No credit card required  •  ✓ 2-minute setup',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/* ----------------------------- FEATURE GRID ---------------------------- */

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    final features = [
      _Feature(
        icon: Icons.upload_file,
        iconColor: Colors.blue,
        title: 'Instant Templates',
        description: 'Upload any Excel/PDF or use AWS/ASME/ISO standards',
      ),
      _Feature(
        icon: Icons.dashboard,
        iconColor: Colors.green,
        title: 'Live Dashboards',
        description: 'Track progress, defects, and KPIs in real-time',
      ),
      _Feature(
        icon: Icons.check_circle,
        iconColor: Colors.orange,
        title: 'Auto Validation',
        description: 'Catch errors before they become costly rework',
      ),
      _Feature(
        icon: Icons.file_download,
        iconColor: Colors.purple,
        title: 'One-Click Reports',
        description: 'Export client-ready PDF/Excel with your branding',
      ),
      _Feature(
        icon: Icons.people,
        iconColor: Colors.teal,
        title: 'Team Collaboration',
        description: 'Role-based access for inspectors and managers',
      ),
      _Feature(
        icon: Icons.security,
        iconColor: Colors.red,
        title: 'Secure & Compliant',
        description: 'Encrypted data storage with audit trails',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dynamic columns based on screen width
        int crossAxisCount;
        double childAspectRatio;
        
        if (constraints.maxWidth > 900) {
          // Desktop: 3 columns
          crossAxisCount = 3;
          childAspectRatio = 1.1;
        } else if (constraints.maxWidth > 600) {
          // Tablet: 2 columns
          crossAxisCount = 2;
          childAspectRatio = 1.15;
        } else {
          // Mobile: 2 columns (compact)
          crossAxisCount = 2;
          childAspectRatio = 0.95;
        }
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: features.length,
          itemBuilder: (context, index) => _FeatureCard(feature: features[index]),
        );
      },
    );
  }
}

class _Feature {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _Feature({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    
    return Card(
      elevation: isDark ? 2 : 1,
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
              decoration: BoxDecoration(
                color: feature.iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
              ),
              child: Icon(
                feature.icon,
                color: feature.iconColor,
                size: isSmallScreen ? 22 : 28,
              ),
            ),
            SizedBox(height: isSmallScreen ? 10 : 16),
            Text(
              feature.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isSmallScreen ? 14 : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Flexible(
              child: Text(
                feature.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  height: 1.4,
                  fontSize: isSmallScreen ? 12 : 14,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- SOCIAL PROOF SECTION -------------------------- */

class _SocialProofSection extends StatelessWidget {
  const _SocialProofSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.grey[900]?.withValues(alpha: 0.5) 
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Trusted by QA/QC Professionals',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isSmallScreen ? 18 : null,
            ),
          ),
          SizedBox(height: isSmallScreen ? 16 : 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: isSmallScreen ? 24 : 48,
            runSpacing: isSmallScreen ? 16 : 24,
            children: [
              _StatCard(
                value: '10,000+',
                label: 'Inspections',
                icon: Icons.assignment_turned_in,
                isSmall: isSmallScreen,
              ),
              _StatCard(
                value: '50+',
                label: 'Companies',
                icon: Icons.business,
                isSmall: isSmallScreen,
              ),
              _StatCard(
                value: '95%',
                label: 'Time Saved',
                icon: Icons.speed,
                isSmall: isSmallScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.isSmall = false,
  });
  
  final String value;
  final String label;
  final IconData icon;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Icon(
          icon,
          size: isSmall ? 28 : 32,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(height: isSmall ? 6 : 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            fontSize: isSmall ? 28 : null,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: isSmall ? 13 : 14,
          ),
        ),
      ],
    );
  }
}

/* ------------------------------ FINAL CTA ------------------------------ */

class _FinalCTA extends StatelessWidget {
  const _FinalCTA({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 24 : 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Ready to modernize your QA/QC workflow?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isSmallScreen ? 20 : null,
            ),
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
          Text(
            'Join teams who\'ve eliminated paperwork and reduced inspection time by 95%',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isSmallScreen ? 14 : 16,
              height: 1.4,
            ),
          ),
          SizedBox(height: isSmallScreen ? 20 : 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                Paths.auth,
                arguments: {'initialMode': 'signup'},
              );
            },
            icon: const Icon(Icons.arrow_forward),
            label: Text(isSmallScreen ? 'Start Free' : 'Start Free Today'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 24 : 32,
                vertical: isSmallScreen ? 14 : 16,
              ),
              textStyle: TextStyle(
                fontSize: isSmallScreen ? 15 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- TOP BAR (responsive) -------------------------- */

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isPhone = width < 640;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      title: const Text(
        'WeldQAi',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      actions: isPhone
          ? const [_MoreMenu(), SizedBox(width: 8)]
          : const [
              _TopLink('How it Works', _ContentSheet.howItWorks),
              _TopLink('FAQ', _ContentSheet.faq),
              _TopLink('Why Us?', _ContentSheet.whyUs),
              _TopLink('Contact', _ContentSheet.contact),
              SizedBox(width: 8),
            ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuItem>(
      tooltip: 'Menu',
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
      icon: const Icon(Icons.more_vert),
    );
  }
}

class _MenuItem {
  final String label;
  final void Function(BuildContext) onTap;
  _MenuItem(this.label, this.onTap);
}

class _TopLink extends StatelessWidget {
  const _TopLink(this.text, this.open);
  final String text;
  final void Function(BuildContext) open;
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => open(context),
      child: Text(text),
    );
  }
}

/* ------------------------------ FOOTER LINKS ------------------------------ */

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
          TextButton(
            onPressed: () => _ContentSheet.about(context),
            child: const Text('About'),
          ),
          TextButton(
            onPressed: () => _ContentSheet.terms(context),
            child: const Text('Terms'),
          ),
          TextButton(
            onPressed: () => _ContentSheet.privacy(context),
            child: const Text('Privacy'),
          ),
          TextButton(
            onPressed: () => _ContentSheet.disclaimer(context),
            child: const Text('Disclaimer'),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- CONTENT & CONTACT UI -------------------------- */

class _ContentSheet {
  static Future<void> _open(
    BuildContext context, {
    required String title,
    required List<_Section> sections,
    bool showContactForm = false,
    Widget? customContent,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final screenW = MediaQuery.of(ctx).size.width;
        final maxWidth = screenW < 720 ? 560.0 : 720.0;
        final rawScale = MediaQuery.of(ctx).textScaleFactor;
        final clampedScale = rawScale.clamp(1.0, 1.2) as double;

        final base = Theme.of(ctx).textTheme;
        final titleStyle = base.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        );
        final sectionStyle = base.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
        final bodyStyle = base.bodyMedium?.copyWith(
          height: 1.4,
        );

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
                      Row(
                        children: [
                          Expanded(
                            child: Text(title, style: titleStyle),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
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
                            if (showContactForm) const _ContactForm(),
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

  static void howItWorks(BuildContext c) => _open(
        c,
        title: 'How WeldQAi Works',
        sections: _copyHowItWorks,
      );

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

  static void contact(BuildContext c) => _open(
        c,
        title: 'Contact WeldQAi',
        sections: [],
        customContent: const _ContactInfo(),
      );

  static final List<_Section> _copyHowItWorks = [
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

  static final List<_Section> _copyFaq = [
    _Section('Who is it for?', [
      'QA/QC inspectors, welding engineers, project managers, fabrication supervisors, and contractors.',
    ]),
    _Section('What standards are supported?', [
      'AWS, ASME, ISO, NACE, and client-specific criteria via custom schemas.',
    ]),
    _Section('Is mobile supported?', [
      'Yes—optimized for laptops and tablets today. Mobile refinements are ongoing.',
    ]),
    _Section('Is data secure?', [
      'Yes. Data is stored in Firebase with encryption at rest and in transit, and access is restricted by roles.',
    ]),
    _Section('How is this better than Excel/PDF?', [
      'Fewer manual errors, standardized outputs, real-time KPIs, and effortless sharing.',
    ]),
  ];

  static final List<_Section> _copyWhyUs = [
    _Section('Built by practitioners', [
      'Designed by people who have lived the welding QA/QC workflow end-to-end.',
    ]),
    _Section('Comprehensive coverage', [
      'Welding operations, NDT, hydrotests, coating, PWHT, welder qualifications—unified in one platform.',
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

  static final List<_Section> _copyAbout = [
    _Section('Our mission', [
      'Bring intelligence and efficiency to welding QA/QC by replacing scattered spreadsheets and paper trails with a smart, cloud-based platform.',
    ]),
    _Section('What we value', [
      'Accuracy, speed, and transparency. We build tools that help teams deliver quality on time and with confidence.',
    ]),
  ];

  static final List<_Section> _copyTerms = [
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

  static final List<_Section> _copyPrivacy = [
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

  static final List<_Section> _copyDisclaimer = [
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

/* ------------------------ CLICKABLE CONTACT INFO ----------------------- */

class _ContactInfo extends StatelessWidget {
  const _ContactInfo();

  Future<void> _launchEmail(BuildContext context, String email) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=WeldQAi Inquiry',
    );
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open email app. Please email us at: $email')),
        );
      }
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
            Text(
              'Get in touch',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Have questions, feedback, or interested in a pilot program?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            
            // General Inquiries
            _EmailButton(
              icon: Icons.email,
              label: 'General Inquiries',
              email: 'info@weldqai.com',
              onTap: () => _launchEmail(context, 'info@weldqai.com'),
            ),
            const SizedBox(height: 12),
            
            // Technical Support
            _EmailButton(
              icon: Icons.support_agent,
              label: 'Technical Support',
              email: 'support@weldqai.com',
              onTap: () => _launchEmail(context, 'support@weldqai.com'),
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'We typically respond within 24 hours during business days.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
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

  final IconData icon;
  final String label;
  final String email;
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
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
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
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios, 
              size: 16, 
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ CONTACT FORM (KEPT FOR REFERENCE) ------------------------------ */

class _ContactForm extends StatefulWidget {
  const _ContactForm();

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

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
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'company': _company.text.trim(),
        'message': _message.text.trim(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent. Thank you!')),
        );
        _formKey.currentState!.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
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

    final fields = [
      Flexible(
        child: TextFormField(
          controller: _name,
          decoration: deco('Name'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ),
      const SizedBox(width: 12, height: 12),
      Flexible(
        child: TextFormField(
          controller: _email,
          decoration: deco('Email'),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            final t = v?.trim() ?? '';
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
                  ? Column(children: fields)
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: fields),
              const SizedBox(height: 12),
              TextFormField(
                controller: _company,
                decoration: deco('Company (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                decoration: deco('Message'),
                maxLines: 6,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Please enter a message' : null,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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