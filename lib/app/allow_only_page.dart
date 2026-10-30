import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../router/models.dart';
import 'devices_cubit.dart';
import 'pair_device_page.dart';
import 'theme.dart';
import 'widgets.dart';

class AllowOnlyPage extends StatefulWidget {
  const AllowOnlyPage({super.key});

  @override
  State<AllowOnlyPage> createState() => _AllowOnlyPageState();
}

class _AllowOnlyPageState extends State<AllowOnlyPage> {
  late final Set<String> _selected;
  final List<Host> _manual = [];

  @override
  void initState() {
    super.initState();
    final snapshot = context.read<DevicesCubit>().state.snapshot!;
    final filter = snapshot.mainFilter!;
    _selected = filter.isAllowOnly
        ? filter.macs.toSet()
        : {
            for (final host in snapshot.hosts)
              if (host.active && host.isWireless) host.mac,
          };
  }

  Future<void> _pairDevice() async {
    final cubit = context.read<DevicesCubit>();
    final confirmed = await showConfirm(
      context,
      title: 'ربط جهاز جديد؟',
      body:
          'الحماية هتتقفل لمدة 3 دقايق عشان الجهاز يقدر يتصل، وبعدها هترجع '
          'لوحدها. الشبكة هتقطع ثواني عند الفتح والقفل، وخليك في الشاشة لحد '
          'ما تخلص.',
      action: 'ابدأ',
    );
    if (!confirmed || !mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const PairDevicePage()),
      ),
    );
  }

  Future<void> _addByMac() async {
    final mac = await showMacSheet(
      context,
      title: 'إضافة جهاز بعنوان MAC',
      action: 'إضافة',
    );
    if (mac == null || !mounted) {
      return;
    }
    final host = context.read<DevicesCubit>().hostForMac(mac);
    setState(() {
      _selected.add(mac);
      if (!host.canRename && !_manual.contains(host)) {
        _manual.add(host);
      }
    });
  }

  Future<void> _enable() async {
    final cubit = context.read<DevicesCubit>();
    final confirmed = await showConfirm(
      context,
      title: 'تفعيل الوضع لـ ${_selected.length} جهاز؟',
      body:
          'أي جهاز مش متعلم عليه هيتقطع من الواي فاي. '
          'الشبكة كلها ممكن تقطع ثواني وقت التطبيق.',
      action: 'تفعيل',
      danger: true,
    );
    if (confirmed && await cubit.enableAllowOnly(_selected) && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _disable() async {
    final cubit = context.read<DevicesCubit>();
    final confirmed = await showConfirm(
      context,
      title: 'إيقاف الوضع؟',
      body: 'كل الأجهزة هتقدر تتصل بالواي فاي تاني.',
      action: 'إيقاف',
    );
    if (confirmed && await cubit.disableAllowOnly() && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DevicesCubit, DevicesState>(
      listenWhen: (previous, current) =>
          current.error != null && previous.error != current.error,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        final snapshot = state.snapshot!;
        final filter = snapshot.mainFilter!;
        final busy = state.busyMac == DevicesCubit.allowOnlyBusyKey;
        final known = {for (final host in snapshot.hosts) host.mac};
        final hosts = [
          ..._manual.where((host) => !known.contains(host.mac)),
          ...snapshot.hosts.where((host) => host.isWireless),
        ]..sort((a, b) => (a.active == b.active) ? 0 : (a.active ? -1 : 1));
        return Scaffold(
          appBar: AppBar(title: const Text('الأجهزة المسموحة')),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _Notice(active: filter.isAllowOnly, ssid: filter.ssid),
                    if (filter.isAllowOnly) ...[
                      const SizedBox(height: 10),
                      AppCard(
                        onTap: _pairDevice,
                        padding: const EdgeInsets.all(12),
                        borderColor: AppColors.accent.withValues(alpha: 0.3),
                        child: const Row(
                          children: [
                            IconTile(
                              icon: Icons.add_link_rounded,
                              color: AppColors.accent,
                              size: 42,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ربط جهاز جديد',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'من غير كتابة: وصله واختاره من القائمة',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    AppCard(
                      onTap: _addByMac,
                      padding: const EdgeInsets.all(12),
                      child: const Row(
                        children: [
                          IconTile(
                            icon: Icons.add_rounded,
                            color: AppColors.accent,
                            size: 42,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'إضافة جهاز بعنوان MAC',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionLabel('اختار الأجهزة', count: hosts.length),
                    for (final host in hosts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SelectableHost(
                          host: host,
                          isSelf: host.mac == snapshot.selfMac,
                          selected: _selected.contains(host.mac),
                          onToggle: () => setState(() {
                            if (!_selected.remove(host.mac)) {
                              _selected.add(host.mac);
                            }
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              _BottomBar(
                count: _selected.length,
                active: filter.isAllowOnly,
                busy: busy,
                onEnable: _enable,
                onDisable: _disable,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.active, required this.ssid});

  final bool active;
  final String ssid;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.warning : AppColors.accent;
    return AppCard(
      borderColor: color.withValues(alpha: 0.25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: active
                ? Icons.gpp_maybe_rounded
                : Icons.verified_user_rounded,
            color: color,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              active
                  ? 'الوضع شغال: الأجهزة المتعلم عليها بس تقدر تتصل بـ $ssid.'
                  : 'حدد مين مسموح له يتصل بـ $ssid. أي جهاز تاني هيتمنع، '
                        'وجهازك هيفضل مسموح دايمًا.',
              style: const TextStyle(height: 1.6, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableHost extends StatelessWidget {
  const _SelectableHost({
    required this.host,
    required this.isSelf,
    required this.selected,
    required this.onToggle,
  });

  final Host host;
  final bool isSelf;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final checked = isSelf || selected;
    return AppCard(
      padding: const EdgeInsets.all(12),
      borderColor: checked
          ? AppColors.accent.withValues(alpha: 0.4)
          : AppColors.border,
      onTap: isSelf ? null : onToggle,
      child: Row(
        children: [
          IconTile(
            icon: deviceIcon(host),
            color: host.active ? AppColors.accent : AppColors.textMuted,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? '${host.displayName} (جهازك)' : host.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  host.mac,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: checked ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: checked ? AppColors.accent : AppColors.textMuted,
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF04211F),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.count,
    required this.active,
    required this.busy,
    required this.onEnable,
    required this.onDisable,
  });

  final int count;
  final bool active;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (active) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDisable,
                  child: const Text('إيقاف الوضع'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onEnable,
                child: busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(active ? 'حفظ التغييرات' : 'تفعيل لـ $count جهاز'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
