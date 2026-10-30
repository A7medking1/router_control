import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../router/mac_input_formatter.dart';
import '../router/models.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.gradient,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color = AppColors.textMuted,
    this.size = 46,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        count == null ? title : '$title  ·  $count',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

IconData deviceIcon(Host host) {
  final name = host.name.toLowerCase();
  bool has(String pattern) => RegExp(pattern).hasMatch(name);
  if (has(r'tv|webos|bravia|roku|chromecast')) {
    return Icons.tv_rounded;
  }
  if (has(r'macbook|laptop|notebook|desktop|windows|\bpc\b')) {
    return Icons.laptop_mac_rounded;
  }
  if (has(r'ipad|tablet|\btab\b')) {
    return Icons.tablet_mac_rounded;
  }
  if (has(
    r'iphone|android|realme|moto|galaxy|redmi|oppo|vivo|xiaomi|oneplus|poco|infinix|tecno|samsung|huawei|honor|nokia',
  )) {
    return Icons.smartphone_rounded;
  }
  return host.isWireless ? Icons.devices_other_rounded : Icons.lan_rounded;
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      content: Text(
        body,
        style: const TextStyle(color: AppColors.textMuted, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: danger ? AppColors.danger : AppColors.accent,
            foregroundColor: const Color(0xFF10171E),
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Returns a normalized MAC address, or null when dismissed.
Future<String?> showMacSheet(
  BuildContext context, {
  required String title,
  required String action,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MacSheet(title: title, action: action),
  );
}

class _MacSheet extends StatefulWidget {
  const _MacSheet({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_MacSheet> createState() => _MacSheetState();
}

class _MacSheetState extends State<_MacSheet> {
  final _input = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _complete => _input.text.length == macTextLength;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) {
      return;
    }
    final match = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}')
        .firstMatch(text);
    if (match == null) {
      setState(() => _error = 'مفيش عنوان MAC في اللي نسخته');
      return;
    }
    _input.value = const MacInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: match.group(0)!),
    );
  }

  void _submit() {
    final mac = parseMac(_input.text);
    if (mac == null) {
      setState(() => _error = 'العنوان ده مش صالح لجهاز واي فاي');
      return;
    }
    Navigator.pop(context, mac);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            const Text(
              'هتلاقيه في إعدادات الواي فاي على الجهاز نفسه.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: const [MacInputFormatter()],
              onSubmitted: (_) => _complete ? _submit() : null,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'AA:BB:CC:11:22:33',
                errorText: _error,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                suffixIcon: _complete && _error == null
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.accent,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste_rounded, size: 19),
                    label: const Text('لصق'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _complete ? _submit : null,
                    child: Text(widget.action),
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

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
