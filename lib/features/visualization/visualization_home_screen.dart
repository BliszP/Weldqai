// lib/features/visualization/visualization_home_screen.dart
import 'package:flutter/material.dart';

/// Minimal KPI launcher screen for the Visualization section.
class VisualizationHomeScreen extends StatefulWidget {
  final String userId; // CHANGED: from projectId to userId

  /// Required: load KPIs once
  final Future<Map<String, num>> Function(String userId, DateTimeRange? range) loadKpis; // CHANGED

  /// Optional: live KPIs stream
  final Stream<Map<String, num>> Function(String userId, DateTimeRange? range)? loadKpisStream; // CHANGED

  /// Navigate to full KPI / Charts
  final VoidCallback onOpenKpis;

  const VisualizationHomeScreen({
    super.key,
    required this.userId, // CHANGED
    required this.loadKpis,
    required this.onOpenKpis,
    this.loadKpisStream,
  });

  @override
  State<VisualizationHomeScreen> createState() => _VisualizationHomeScreenState();
}

class _VisualizationHomeScreenState extends State<VisualizationHomeScreen> {
  DateTimeRange? _range;
  late Future<Map<String, num>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadKpis(widget.userId, _range); // CHANGED
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.loadKpis(widget.userId, _range); // CHANGED
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialFirst = now.subtract(const Duration(days: 30));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range ?? DateTimeRange(start: initialFirst, end: now),
      saveText: 'Apply',
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _future = widget.loadKpis(widget.userId, _range); // CHANGED
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildBody(Map<String, num>? data) {
      final m = data ?? const {};

      final totalWelds  = (m['totalWelds'] ?? 0).toInt();
      final ndtPass     = (m['ndtPassPercent'] ?? m['ndtPassPct'] ?? 0).toDouble();
      final repairsOpen = (m['repairsOpen'] ?? 0).toInt();

      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    title: 'Total Welds',
                    value: '$totalWelds',
                    icon: Icons.merge_type,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'NDT Pass %',
                    value: '${ndtPass.toStringAsFixed(1)}%',
                    icon: Icons.analytics_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Repairs Open',
                    value: '$repairsOpen',
                    icon: Icons.build_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.show_chart),
                title: const Text('Weld / Report KPIs'),
                subtitle: const Text('Open charts (NDT pass rate, productivity, repairs).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onOpenKpis,
              ),
            ),
            if (_range != null) ...[
              const SizedBox(height: 8),
              Text(
                'Range: ${_fmtDate(_range!.start)} — ${_fmtDate(_range!.end)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }

    final streamProvider = widget.loadKpisStream;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualization'),
        actions: [
          IconButton(
            tooltip: 'Date range',
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: streamProvider == null
          ? FutureBuilder<Map<String, num>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorBox(message: 'Failed to load KPIs:\n${snap.error}');
                }
                return buildBody(snap.data);
              },
            )
          : StreamBuilder<Map<String, num>>(
              stream: streamProvider(widget.userId, _range), // CHANGED
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorBox(message: 'Failed to load KPIs (live):\n${snap.error}');
                }
                _future = widget.loadKpis(widget.userId, _range); // CHANGED
                return buildBody(snap.data);
              },
            ),
    );
  }

  String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _two(int v) => v < 10 ? '0$v' : '$v';
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}