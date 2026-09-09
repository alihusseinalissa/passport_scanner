import 'package:flutter/material.dart';
import 'package:passport_scanner/passport_scanner.dart';

import 'main.dart';

/// What the scanner is currently telling the user, driven by the widget's
/// throttled failure callbacks.
enum _ScanHint {
  searching(
    Icons.center_focus_weak_rounded,
    'Align the two lines at the bottom of the page',
  ),
  noMrz(
    Icons.search_off_rounded,
    'No machine-readable zone in view',
  ),
  unreadable(
    Icons.blur_on_rounded,
    'Lines found but unreadable — reduce glare and hold steady',
  );

  const _ScanHint(this.icon, this.message);

  final IconData icon;
  final String message;
}

/// Full-screen capture surface. Pops a [Scan] on success, or `null` if the
/// user backs out.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  _ScanHint _hint = _ScanHint.searching;

  void _setHint(_ScanHint hint) {
    if (!mounted || _hint == hint) return;
    setState(() => _hint = hint);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PassportScannerWidget(
            precision: 2,
            showFlashButton: true,
            onNoMrzFound: () => _setHint(_ScanHint.noMrz),
            onParsingFailed: (_) => _setHint(_ScanHint.unreadable),
            onScanned: (result, imagePath) {
              Navigator.of(context).pop(Scan(result, imagePath));
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _GlassButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Cancel scan',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: _HintPill(hint: _hint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.hint});

  final _ScanHint hint;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(hint),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hint.icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                hint.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        color: Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}
