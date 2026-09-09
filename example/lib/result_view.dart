import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz_parser/mrz_parser.dart';

import 'mrz_format.dart';

/// Full presentation of a parsed MRZ: the capture, a validity summary and
/// every field the parser produced, grouped the way they read on the document.
class ScanResultView extends StatelessWidget {
  const ScanResultView({
    super.key,
    required this.result,
    required this.imagePath,
    required this.scannedAt,
    required this.sourceIcon,
    required this.sourceLabel,
  });

  final MRZResult result;
  final String? imagePath;
  final DateTime scannedAt;

  /// How this scan was captured — camera or gallery — shown in the footer.
  final IconData sourceIcon;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final optionalData = (result.personalNumber2 ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DocumentHero(result: result, imagePath: imagePath),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.person_outline_rounded,
          title: 'Holder',
          fields: [
            _Field(label: 'Surnames', value: result.surnames),
            _Field(label: 'Given names', value: result.givenNames),
            _Field(
              label: 'Date of birth',
              value: formatDate(result.birthDate),
              hint: '${ageInYears(result.birthDate)} years old',
              copyValue: formatDate(result.birthDate),
            ),
            _Field(label: 'Sex', value: sexLabel(result.sex)),
            _Field(
              label: 'Nationality',
              value: countryLabel(result.nationalityCountryCode),
              hint: result.nationalityCountryCode,
              leading: countryFlag(result.nationalityCountryCode),
              copyValue: result.nationalityCountryCode,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.badge_outlined,
          title: 'Document',
          fields: [
            _Field(
              label: 'Document number',
              value: result.documentNumber,
              monospace: true,
            ),
            _Field(
              label: 'Type',
              value: documentTypeLabel(result.documentType),
              hint: result.documentType,
            ),
            _Field(
              label: 'Issuing country',
              value: countryLabel(result.countryCode),
              hint: result.countryCode,
              leading: countryFlag(result.countryCode),
              copyValue: result.countryCode,
            ),
            _Field(
              label: 'Date of expiry',
              value: formatDate(result.expiryDate),
              hint: expiryLabel(result.expiryDate),
              copyValue: formatDate(result.expiryDate),
            ),
            if (result.personalNumber.trim().isNotEmpty)
              _Field(
                label: 'Personal number',
                value: result.personalNumber,
                monospace: true,
              ),
            if (optionalData.isNotEmpty)
              _Field(
                label: 'Optional data',
                value: optionalData,
                monospace: true,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _ScanMetaFooter(
          scannedAt: scannedAt,
          sourceIcon: sourceIcon,
          sourceLabel: sourceLabel,
        ),
      ],
    );
  }
}

/// Capture, name and validity chips — the part of the screen you read first.
class _DocumentHero extends StatelessWidget {
  const _DocumentHero({required this.result, required this.imagePath});

  final MRZResult result;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final expired = daysUntil(result.expiryDate) < 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CaptureImage(result: result, imagePath: imagePath),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.givenNames.trim().isEmpty
                      ? result.surnames
                      : result.givenNames,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                Text(
                  result.surnames.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(
                      icon: expired
                          ? Icons.error_outline_rounded
                          : Icons.verified_outlined,
                      label: expiryLabel(result.expiryDate),
                      tone: expired ? _ChipTone.alert : _ChipTone.positive,
                    ),
                    _Chip(
                      icon: Icons.tag_rounded,
                      label: result.documentNumber,
                      monospace: true,
                    ),
                    _Chip(
                      icon: Icons.public_rounded,
                      label:
                          '${countryFlag(result.nationalityCountryCode) ?? ''} '
                                  '${result.nationalityCountryCode}'
                              .trim(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureImage extends StatelessWidget {
  const _CaptureImage({required this.result, required this.imagePath});

  final MRZResult result;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = imagePath;
    final file = path == null ? null : File(path);

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: file == null || !file.existsSync()
          ? _PlaceholderCapture(result: result)
          : Semantics(
              label: 'Captured document image. Tap to view full size.',
              button: true,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FullScreenImage(file: file),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      file,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _PlaceholderCapture(result: result),
                    ),
                    // Keeps the badge legible over an arbitrary photo.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [Colors.black45, Colors.transparent],
                          stops: [0, 0.45],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_out_map_rounded, size: 14),
                              SizedBox(width: 6),
                              Text('Capture', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Shown when the frame could not be saved — the scan itself is still valid.
class _PlaceholderCapture extends StatelessWidget {
  const _PlaceholderCapture({required this.result});

  final MRZResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: 36,
          backgroundColor: colors.surface.withValues(alpha: 0.7),
          child: Text(
            initials(result),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Capture'),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// One titled group of fields.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.fields,
  });

  final IconData icon;
  final String title;
  final List<_Field> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final (index, field) in fields.indexed) ...[
            if (index > 0)
              Divider(height: 1, indent: 20, color: colors.outlineVariant),
            _FieldTile(field: field),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A single MRZ field: what to show, and what lands on the clipboard.
class _Field {
  const _Field({
    required this.label,
    required this.value,
    this.hint,
    this.leading,
    this.monospace = false,
    String? copyValue,
  }) : _copyValue = copyValue;

  final String label;
  final String value;

  /// Secondary line: derived context (age, expiry distance) or the raw code
  /// behind a resolved value.
  final String? hint;

  /// Emoji rendered before the value — a flag, in practice.
  final String? leading;
  final bool monospace;
  final String? _copyValue;

  String get copyValue => _copyValue ?? value;
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({required this.field});

  final _Field field;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: field.copyValue));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 260,
          duration: const Duration(seconds: 2),
          content: Text('${field.label} copied'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final displayValue = field.value.trim().isEmpty ? '—' : field.value;

    return InkWell(
      onTap: () => _copy(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (field.leading != null) ...[
                        Text(
                          field.leading!,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          displayValue,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontFamily: field.monospace ? 'monospace' : null,
                            letterSpacing: field.monospace ? 1.1 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (field.hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      field.hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.copy_rounded,
              size: 16,
              color: colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanMetaFooter extends StatelessWidget {
  const _ScanMetaFooter({
    required this.scannedAt,
    required this.sourceIcon,
    required this.sourceLabel,
  });

  final DateTime scannedAt;
  final IconData sourceIcon;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time =
        '${scannedAt.hour.toString().padLeft(2, '0')}:'
        '${scannedAt.minute.toString().padLeft(2, '0')}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(sourceIcon, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Check digits verified · read from the $sourceLabel at $time',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

enum _ChipTone { neutral, positive, alert }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.tone = _ChipTone.neutral,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      _ChipTone.positive => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      _ChipTone.alert => (colors.errorContainer, colors.onErrorContainer),
      _ChipTone.neutral => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
