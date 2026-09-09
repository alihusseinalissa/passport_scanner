import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:passport_scanner/passport_scanner.dart';

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

/// Which of the package's two entry points produced a scan.
enum ScanSource {
  camera(Icons.qr_code_scanner_rounded, 'camera'),
  gallery(Icons.photo_library_outlined, 'gallery');

  const ScanSource(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// A scan, plus the image it came from, where it came from and when.
class Scan {
  Scan(this.result, this.imagePath, this.source) : at = DateTime.now();

  final MRZResult result;
  final String? imagePath;
  final ScanSource source;
  final DateTime at;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Scan? _scan;

  /// True while a picked image is being read — OCR of a full-resolution photo
  /// takes a moment, and may run several orientations before it gives up.
  bool _reading = false;

  /// Live camera scan: [PassportScannerWidget], hosted by [ScannerPage].
  Future<void> _scanWithCamera() async {
    if (_reading) return;
    final scan = await Navigator.of(
      context,
    ).push<Scan>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (scan == null || !mounted) return;
    setState(() => _scan = scan);
  }

  /// Still-image scan: the package opens the photo picker and reads the MRZ
  /// from whatever the user chooses.
  Future<void> _scanFromGallery() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final scan = await scanPassportFromGallery();
      if (!mounted) return;
      if (scan.isSuccess) {
        setState(
          () => _scan = Scan(scan.result!, scan.imagePath, ScanSource.gallery),
        );
      } else if (scan.failure != PassportScanFailure.cancelled) {
        _showMessage(_failureMessage(scan.failure!));
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  String _failureMessage(PassportScanFailure failure) => switch (failure) {
    PassportScanFailure.cancelled => 'Scan cancelled',
    PassportScanFailure.unreadableImage => 'That image could not be read',
    PassportScanFailure.noMrzFound =>
      'No machine-readable zone found in that image',
    PassportScanFailure.invalidMrz =>
      'The two lines were found but failed their check digits — '
          'try a sharper photo',
  };

  Future<void> _copyAll() async {
    final scan = _scan;
    if (scan == null) return;
    await Clipboard.setData(ClipboardData(text: resultAsText(scan.result)));
    if (!mounted) return;
    _showMessage('All fields copied');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clear() => setState(() => _scan = null);

  @override
  Widget build(BuildContext context) {
    final scan = _scan;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
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
                      ? _EmptyState(
                          onScan: _scanWithCamera,
                          onPickImage: _scanFromGallery,
                        )
                      : ScanResultView(
                          result: scan.result,
                          imagePath: scan.imagePath,
                          scannedAt: scan.at,
                          sourceIcon: scan.source.icon,
                          sourceLabel: scan.source.label,
                        ),
                ),
              ),
            ],
          ),
          if (_reading) const _ReadingOverlay(),
        ],
      ),
      bottomNavigationBar: scan == null
          ? null
          : _BottomBar(
              onScan: _reading ? null : _scanWithCamera,
              onPickImage: _reading ? null : _scanFromGallery,
              onCopyAll: _copyAll,
            ),
    );
  }
}

/// Covers the screen while a picked image is read, so the app cannot be driven
/// into a second scan mid-flight.
class _ReadingOverlay extends StatelessWidget {
  const _ReadingOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.scrim.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text('Reading the image…', style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan, required this.onPickImage});

  final VoidCallback onScan;
  final VoidCallback onPickImage;

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
            'bottom of a passport, or pick a photo you already have. Every '
            'field is read from the MRZ and verified against its check digits.',
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
          label: const Text('Scan with camera'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            textStyle: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onPickImage,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from gallery'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
    (
      Icons.photo_library_outlined,
      'A gallery photo works too, in any orientation',
    ),
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
  const _BottomBar({
    required this.onScan,
    required this.onPickImage,
    required this.onCopyAll,
  });

  final VoidCallback? onScan;
  final VoidCallback? onPickImage;
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
              onPressed: onPickImage,
              tooltip: 'Choose from gallery',
              iconSize: 22,
              padding: const EdgeInsets.all(16),
              icon: const Icon(Icons.photo_library_outlined),
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
