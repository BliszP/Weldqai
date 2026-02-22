// lib/features/visualization/visualization_kpi_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:weldqai_app/core/repositories/metrics_repository.dart';

/// KPIs & Charts (responsive, with summaries and export)
class VisualizationKpiScreen extends StatefulWidget {
  const VisualizationKpiScreen({
    super.key,
    required this.userId, // CHANGED: from projectId to userId
    required this.repo,
  });

  final String userId; // CHANGED
  final MetricsRepository repo;

  @override
  State<VisualizationKpiScreen> createState() => _VisualizationKpiScreenState();
}

class _VisualizationKpiScreenState extends State<VisualizationKpiScreen> {
  DateTime? _start;
  DateTime? _end;

  final _keys = List<GlobalKey>.generate(8, (_) => GlobalKey());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPIs & Charts'),
        actions: [
          IconButton(
            tooltip: 'Pick range',
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth;
          final columns = width >= 1400 ? 3 : (width >= 900 ? 2 : 1);

          return GridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 1.25 : (columns == 2 ? 1.6 : 1.7),
            children: [
              // 1) NDT pass rate — last 6 months
              _ChartCard(
                title: 'NDT Pass Rate (%) — last 6 months',
                boundaryKey: _keys[0],
                chart: FutureBuilder<List<double>>(
                  future: widget.repo.ndtPassRateLast6Months(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final v = (snap.data ?? const <double>[]);
                    return _LineChart6(values: v);
                  },
                ),
                summary: FutureBuilder<List<double>>(
                  future: widget.repo.ndtPassRateLast6Months(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final v = (snap.data ?? const <double>[]);
                    final last = v.isNotEmpty ? v.last : 0.0;
                    final avg = v.isNotEmpty ? (v.reduce((a, b) => a + b) / v.length) : 0.0;
                    return _SummaryList(items: {
                      'Latest': '${last.toStringAsFixed(1)}%',
                      '6-mo Avg': '${avg.toStringAsFixed(1)}%',
                      'Points': '${v.length}',
                    });
                  },
                ),
              ),

              // 2) Welds per day — last 4 days
              _ChartCard(
                title: 'Welds per day — last 4 days',
                boundaryKey: _keys[1],
                chart: FutureBuilder<List<int>>(
                  future: widget.repo.weldsPerDayLast7(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final src = (snap.data ?? const <int>[]);
                    final v = src.length <= 4 ? List<int>.from(src) : src.sublist(src.length - 4);
                    return _BarChartSimple(values: v);
                  },
                ),
                summary: FutureBuilder<List<int>>(
                  future: widget.repo.weldsPerDayLast7(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final src = (snap.data ?? const <int>[]);
                    final v = src.length <= 4 ? List<int>.from(src) : src.sublist(src.length - 4);
                    final last = v.isNotEmpty ? v.last : 0;
                    final avg = v.isNotEmpty ? (v.reduce((a, b) => a + b) / v.length) : 0.0;
                    final total = v.isNotEmpty ? v.reduce((a, b) => a + b) : 0;
                    return _SummaryList(items: {
                      'Latest': '$last',
                      '4-day Avg': avg.toStringAsFixed(1),
                      '4-day Total': '$total',
                    });
                  },
                ),
              ),

              // 3) Repairs — open vs closed
              _ChartCard(
                title: 'Repairs — open vs closed',
                boundaryKey: _keys[2],
                chart: FutureBuilder<Map<String, int>>(
                  future: widget.repo.repairsOpenClosed(
                    widget.userId, // CHANGED
                    start: _start,
                    end: _end,
                  ),
                  builder: (c, snap) =>
                      _PieOpenClosed(m: snap.data ?? const {'Open': 0, 'Closed': 0}),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.repairsOpenClosed(
                    widget.userId, // CHANGED
                    start: _start,
                    end: _end,
                  ),
                  builder: (c, snap) {
                    final m = snap.data ?? const {'Open': 0, 'Closed': 0};
                    final open = m['Open'] ?? 0;
                    final closed = m['Closed'] ?? 0;
                    return _SummaryList(items: {
                      'Open': '$open',
                      'Closed': '$closed',
                      'Total': '${open + closed}',
                    });
                  },
                ),
              ),

              // 4) Avg days to close (repairs)
              _ChartCard(
                title: 'Avg days to close (repairs)',
                boundaryKey: _keys[3],
                chart: FutureBuilder<double>(
                  future: widget.repo.avgRepairDaysToClose(
                    widget.userId, // CHANGED
                    start: _start,
                    end: _end,
                  ),
                  builder: (c, snap) => _SingleNumber(
                    value: (snap.data ?? 0.0).toDouble(),
                    suffix: ' days',
                  ),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.repairsOpenClosed(
                    widget.userId, // CHANGED
                    start: _start,
                    end: _end,
                  ),
                  builder: (c, snap) {
                    final m = snap.data ?? const {'Open': 0, 'Closed': 0};
                    return _SummaryList(items: {
                      'Open': '${m['Open'] ?? 0}',
                      'Closed': '${m['Closed'] ?? 0}',
                    });
                  },
                ),
              ),

              // 5) Top defects — last 30 days
              _ChartCard(
                title: 'Top defects — last 30 days',
                boundaryKey: _keys[4],
                chart: FutureBuilder<Map<String, int>>(
                  future: widget.repo.defectBreakdown30d(widget.userId), // CHANGED
                  builder: (c, snap) => _BarsFromMap(m: snap.data ?? const {}),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.defectBreakdown30d(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final m = snap.data ?? const <String, int>{};
                    final total = m.values.fold<int>(0, (a, b) => a + b);
                    final top = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                        .take(1)
                        .toList();
                    final topKey = top.isNotEmpty ? top.first.key : '-';
                    final topVal = top.isNotEmpty ? top.first.value : 0;
                    return _SummaryList(items: {
                      'Total': '$total',
                      'Top': '$topKey ($topVal)',
                    });
                  },
                ),
              ),

              // 6) Inspector throughput — last 7 days
              _ChartCard(
                title: 'Inspector throughput — last 7 days',
                boundaryKey: _keys[5],
                chart: FutureBuilder<Map<String, int>>(
                  future: widget.repo.inspectorThroughput7(widget.userId), // CHANGED
                  builder: (c, snap) => _BarsFromMap(m: snap.data ?? const {}),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.inspectorThroughput7(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final m = snap.data ?? const <String, int>{};
                    final total = m.values.fold<int>(0, (a, b) => a + b);
                    final top = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                        .take(1)
                        .toList();
                    final name = top.isNotEmpty ? top.first.key : '-';
                    final n = top.isNotEmpty ? top.first.value : 0;
                    return _SummaryList(items: {
                      'Total': '$total',
                      'Top insp.': '$name ($n)',
                    });
                  },
                ),
              ),

              // 7) Welder productivity — last 7 days
              _ChartCard(
                title: 'Welder productivity — last 7 days',
                boundaryKey: _keys[6],
                chart: FutureBuilder<Map<String, int>>(
                  future: widget.repo.welderProductivity7(widget.userId), // CHANGED
                  builder: (c, snap) => _BarsFromMap(m: snap.data ?? const {}),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.welderProductivity7(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final m = snap.data ?? const <String, int>{};
                    final total = m.values.fold<int>(0, (a, b) => a + b);
                    final top = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                        .take(1)
                        .toList();
                    final name = top.isNotEmpty ? top.first.key : '-';
                    final n = top.isNotEmpty ? top.first.value : 0;
                    return _SummaryList(items: {
                      'Total': '$total',
                      'Top welder': '$name ($n)',
                    });
                  },
                ),
              ),

              // 8) Heat input distribution — last 30 days
              _ChartCard(
                title: 'Heat input distribution — last 30 days',
                boundaryKey: _keys[7],
                chart: FutureBuilder<Map<String, int>>(
                  future: widget.repo.heatInputDistribution30d(widget.userId), // CHANGED
                  builder: (c, snap) => _BarsFromMap(m: snap.data ?? const {}),
                ),
                summary: FutureBuilder<Map<String, int>>(
                  future: widget.repo.heatInputDistribution30d(widget.userId), // CHANGED
                  builder: (c, snap) {
                    final m = snap.data ?? const <String, int>{};
                    final total = m.values.fold<int>(0, (a, b) => a + b);
                    final bucketCount = m.length;
                    return _SummaryList(items: {
                      'Buckets': '$bucketCount',
                      'Total': '$total',
                    });
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2, 1, 1);
    final initStart = _start ?? now.subtract(const Duration(days: 30));
    final initEnd = _end ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: now,
      initialDateRange: DateTimeRange(start: initStart, end: initEnd),
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }
}

// ============================== Widgets =====================================

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.boundaryKey,
    required this.chart,
    required this.summary,
  });

  final String title;
  final GlobalKey boundaryKey;
  final Widget chart;
  final Widget summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: t.titleMedium)),
                PopupMenuButton<String>(
                  tooltip: 'Export',
                  onSelected: (v) async {
                    if (v == 'png') {
                      await ChartExporter.exportPng(boundaryKey, fileNameHint: title);
                    } else if (v == 'pdf') {
                      await ChartExporter.exportPdf(boundaryKey, title: title);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'png', child: Text('Export PNG')),
                    PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                  ],
                  child: const Icon(Icons.more_vert),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: chart,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: summary,
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

class _SummaryList extends StatelessWidget {
  const _SummaryList({required this.items});
  final Map<String, String> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (items.isEmpty) return const _EmptyChart();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in items.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(e.key, style: t.bodyMedium)),
                Text(e.value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineChart6 extends StatelessWidget {
  const _LineChart6({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final v = values.isEmpty ? List<double>.filled(6, 0) : values;
    final spots = <FlSpot>[
      for (int i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i]),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            dotData: const FlDotData(show: false),
          ),
        ],
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _BarChartSimple extends StatelessWidget {
  const _BarChartSimple({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final v = values.isEmpty ? List<int>.filled(4, 0) : values;
    final groups = <BarChartGroupData>[
      for (int i = 0; i < v.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: v[i].toDouble())],
        ),
    ];
    return BarChart(
      BarChartData(
        barGroups: groups,
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _BarsFromMap extends StatelessWidget {
  const _BarsFromMap({required this.m});
  final Map<String, int> m;

  @override
  Widget build(BuildContext context) {
    if (m.isEmpty) return const _EmptyChart();

    final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.length > 10 ? sorted.sublist(0, 10) : sorted;

    final groups = <BarChartGroupData>[
      for (int i = 0; i < top.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: top[i].value.toDouble())],
        ),
    ];

    return BarChart(
      BarChartData(
        barGroups: groups,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _PieOpenClosed extends StatelessWidget {
  const _PieOpenClosed({required this.m});
  final Map<String, int> m;

  @override
  Widget build(BuildContext context) {
    final open = m['Open'] ?? 0;
    final closed = m['Closed'] ?? 0;

    final sections = <PieChartSectionData>[
      PieChartSectionData(value: closed.toDouble(), title: 'Closed'),
      PieChartSectionData(value: open.toDouble(), title: 'Open'),
    ];

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 40,
              sectionsSpace: 2,
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _SingleNumber extends StatelessWidget {
  const _SingleNumber({required this.value, this.suffix = ''});
  final double value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '${value.toStringAsFixed(1)}$suffix',
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No data for selected range', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class ChartExporter {
  static Future<Uint8List?> _capturePng(GlobalKey key) async {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final ui.Image image = await renderObject.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<void> exportPng(GlobalKey boundaryKey, {required String fileNameHint}) async {
    final bytes = await _capturePng(boundaryKey);
    if (bytes == null) return;
    await Printing.sharePdf(
      bytes: await _wrapSingleImagePdf(bytes),
      filename: '${_safe(fileNameHint)}.pdf',
    );
  }

  static Future<void> exportPdf(GlobalKey boundaryKey, {required String title}) async {
    final bytes = await _capturePng(boundaryKey);
    if (bytes == null) return;
    await Printing.sharePdf(
      bytes: await _wrapSingleImagePdf(bytes),
      filename: '${_safe(title)}.pdf',
    );
  }

  static Future<Uint8List> _wrapSingleImagePdf(Uint8List png) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.a4.landscape,
        build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png))),
      ),
    );
    return doc.save();
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}