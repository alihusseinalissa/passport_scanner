import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz_parser/mrz_parser.dart';

import 'mrz_format.dart';
import 'result_view.dart';
import 'scanner_page.dart';

void main() {
  runApp(const PassportScannerDemoApp());
}

const _seedColor = Color(0xFF2E5AAC);

class PassportScannerDemoApp extends StatelessWidget {
  const PassportScannerDemoApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passport Scanner',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomePage(),
    );
  }
}

/// A scan, plus the frame it came from and when it happened.
class Scan {
  Scan(this.result, this.imagePath) : at = DateTime.now();

  final MRZResult result;
  final String? imagePath;
  final DateTime at;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Scan? _scan;

  Future<void> _startScan() async {
    final scan = await Navigator.of(context).push<Scan>(
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (scan == null || !mounted) return;
    setState(() => _scan = scan);
  }

  Future<void> _copyAll() async {
    final scan = _scan;
    if (scan == null) return;
    await Clipboard.setData(ClipboardData(text: resultAsText(scan.result)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('All fields copied')));
  }

  void _clear() => setState(() => _scan = null);

  @override
  Widget build(BuildContext context) {
    final scan = _scan;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Passport Scanner'),
            actions: [
              if (scan != null) ...[
                IconButton(
                  onPressed: _copyAll,
                  tooltip: 'Copy all fields',
                  icon: const Icon(Icons.copy_all_rounded),
                ),
                IconButton(
                  onPressed: _clear,
                  tooltip: 'Clear result',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: scan == null
                  ? _EmptyState(onScan: _startScan)
                  : ScanResultView(
                      result: scan.result,
                      imagePath: scan.imagePath,
                      scannedAt: scan.at,
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: scan == null
          ? null
          : _BottomBar(onScan: _startScan, onCopyAll: _copyAll),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primaryContainer, colors.secondaryContainer],
            ),
          ),
          child: Icon(
            Icons.document_scanner_outlined,
            size: 56,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'No document scanned yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Point the camera at the two machine-readable lines at the '
            'bottom of a passport. Every field is read from the MRZ and '
            'verified against its check digits.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan a document'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            textStyle: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 40),
        const _TipsCard(),
      ],
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  static const _tips = [
    (Icons.wb_sunny_outlined, 'Use even lighting and avoid glare on the page'),
    (Icons.crop_free_rounded, 'Fit both MRZ lines inside the frame'),
    (Icons.pan_tool_outlined, 'Hold steady — two matching reads are required'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FOR A CLEAN READ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primary,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          for (final (icon, text) in _tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: colors.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onScan, required this.onCopyAll});

  final VoidCallback onScan;
  final VoidCallback onCopyAll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan another'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: onCopyAll,
              tooltip: 'Copy all fields',
              iconSize: 22,
              padding: const EdgeInsets.all(16),
              icon: const Icon(Icons.copy_all_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
