import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../router/filter_plan.dart';
import '../router/models.dart';
import '../router/router_repository.dart';
import 'allow_only_page.dart';
import 'auth_cubit.dart';
import 'devices_cubit.dart';
import 'theme.dart';
import 'url_filter_page.dart';
import 'widgets.dart';

enum _Segment { all, online, blocked }

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<DevicesCubit>().refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DevicesCubit>().refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<DevicesCubit, DevicesState>(
          listenWhen: (previous, current) =>
              current.error != null && previous.error != current.error,
          listener: (context, state) => showError(context, state.error!),
          builder: (context, state) {
            final snapshot = state.snapshot;
            if (snapshot == null) {
              return state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _RetryView(message: state.error);
            }
            return _Dashboard(snapshot: snapshot, busyMac: state.busyMac);
          },
        ),
      ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(
              icon: Icons.wifi_off_rounded,
              color: AppColors.danger,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? 'مفيش بيانات',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.read<DevicesCubit>().refresh(),
              child: const Text('حاول تاني'),
            ),
            TextButton(
              onPressed: () => context.read<AuthCubit>().logout(),
              child: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.snapshot, this.busyMac});

  final RouterSnapshot snapshot;
  final String? busyMac;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  _Segment _segment = _Segment.all;
  String _query = '';

  bool _matches(Host host) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        host.displayName.toLowerCase().contains(query) ||
        host.ip.contains(query) ||
        host.mac.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final hosts = snapshot.hosts.where(_matches).toList();
    final blocked = hosts.where(snapshot.isBlocked).toList();
    final others = hosts.where((h) => !snapshot.isBlocked(h));
    final online = others.where((h) => h.active).toList();
    final offline = others.where((h) => !h.active).toList();
    final onlineTotal = snapshot.hosts.where((h) => h.active).length;

    return RefreshIndicator(
      onRefresh: () => context.read<DevicesCubit>().refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(ssid: snapshot.mainFilter?.ssid, onAddMac: _blockByMac),
          const SizedBox(height: 16),
          _OverviewCard(
            online: onlineTotal,
            total: snapshot.hosts.length,
            traffic: snapshot.traffic,
          ),
          const SizedBox(height: 12),
          _QuickActions(snapshot: snapshot),
          const SizedBox(height: 18),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم أو IP أو MAC',
              prefixIcon: Icon(Icons.search_rounded),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          _SegmentBar(
            value: _segment,
            onChanged: (segment) => setState(() => _segment = segment),
          ),
          if (_segment != _Segment.online) ..._section('محظور', blocked),
          if (_segment != _Segment.blocked) ..._section('متصل دلوقتي', online),
          if (_segment == _Segment.all) ..._section('غير متصل', offline),
          if (_isEmpty(blocked, online, offline)) const _EmptyList(),
        ],
      ),
    );
  }

  Future<void> _blockByMac() async {
    final cubit = context.read<DevicesCubit>();
    final mac = await showMacSheet(
      context,
      title: 'حظر جهاز بعنوان MAC',
      action: 'متابعة',
    );
    if (mac == null || !mounted) {
      return;
    }
    final host = cubit.hostForMac(mac);
    final plan = cubit.previewBlock(host);
    if (plan == null) {
      return;
    }
    final confirmed = await showConfirm(
      context,
      title: 'حظر $mac؟',
      body: _blockWarning(widget.snapshot, host, plan),
      action: 'حظر',
      danger: true,
    );
    if (confirmed) {
      await cubit.block(host, plan);
    }
  }

  bool _isEmpty(List<Host> blocked, List<Host> online, List<Host> offline) =>
      switch (_segment) {
        _Segment.all => blocked.isEmpty && online.isEmpty && offline.isEmpty,
        _Segment.online => online.isEmpty,
        _Segment.blocked => blocked.isEmpty,
      };

  List<Widget> _section(String title, List<Host> hosts) {
    if (hosts.isEmpty) {
      return const [];
    }
    return [
      SectionLabel(title, count: hosts.length),
      for (final host in hosts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HostCard(
            host: host,
            snapshot: widget.snapshot,
            busyMac: widget.busyMac,
          ),
        ),
    ];
  }
}

String _blockWarning(RouterSnapshot snapshot, Host host, FilterPlan plan) {
  final warning = plan.replacesStoredList
      ? '\n\nالقائمة القديمة المتسجلة على الراوتر '
            '(${snapshot.filterFor(host)!.macs.length} جهاز) هتتبدل بالجهاز '
            'ده، ونسخة منها هتتحفظ على الموبايل.'
      : '';
  return 'الجهاز مش هيقدر يتصل بالواي فاي. الشبكة ممكن تقطع ثواني '
      'على كل الأجهزة وقت تطبيق التغيير.$warning';
}

class _Header extends StatelessWidget {
  const _Header({required this.onAddMac, this.ssid});

  final VoidCallback onAddMac;
  final String? ssid;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'الشبكة شغالة',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
              Text(
                ssid ?? 'شبكتي',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'حظر جهاز بعنوان MAC',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textMuted,
          ),
          icon: const Icon(Icons.add_rounded, size: 22),
          onPressed: onAddMac,
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'تسجيل الخروج',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textMuted,
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          onPressed: () => context.read<AuthCubit>().logout(),
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.online,
    required this.total,
    required this.traffic,
  });

  final int online;
  final int total;
  final Traffic? traffic;

  @override
  Widget build(BuildContext context) {
    final traffic = this.traffic;
    return AppCard(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.accent.withValues(alpha: 0.22),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [AppColors.accentDeep, AppColors.surface],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: total == 0 ? 0 : online / total,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.border,
                    ),
                    Center(
                      child: Text(
                        '$online',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'جهاز متصل دلوقتي',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'من $total جهاز معروف للراوتر',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (traffic != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TrafficStat(
                    icon: Icons.south_rounded,
                    label: 'تحميل',
                    value: _formatBytes(traffic.downloaded),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrafficStat(
                    icon: Icons.north_rounded,
                    label: 'رفع',
                    value: _formatBytes(traffic.uploaded),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

class _TrafficStat extends StatelessWidget {
  const _TrafficStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const Spacer(),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.snapshot});

  final RouterSnapshot snapshot;

  void _openAllowOnly(BuildContext context) {
    final cubit = context.read<DevicesCubit>();
    if (snapshot.mainFilter == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const AllowOnlyPage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowOnly = snapshot.mainFilter?.isAllowOnly ?? false;
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.verified_user_rounded,
            title: 'الأجهزة المسموحة',
            subtitle: allowOnly ? 'شغال' : 'مقفول',
            color: allowOnly ? AppColors.warning : AppColors.accent,
            onTap: () => _openAllowOnly(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.public_off_rounded,
            title: 'حجب المواقع',
            subtitle: 'إدارة القائمة',
            color: AppColors.accent,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UrlFilterPage()),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 40),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(subtitle, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.value, required this.onChanged});

  final _Segment value;
  final ValueChanged<_Segment> onChanged;

  static const _labels = {
    _Segment.all: 'الكل',
    _Segment.online: 'متصل',
    _Segment.blocked: 'محظور',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final entry in _labels.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: value == entry.key
                        ? AppColors.surfaceRaised
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: value == entry.key
                          ? AppColors.text
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Text(
        'مفيش أجهزة هنا',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.snapshot, this.busyMac});

  final Host host;
  final RouterSnapshot snapshot;
  final String? busyMac;

  @override
  Widget build(BuildContext context) {
    final blocked = snapshot.isBlocked(host);
    final isSelf = host.mac == snapshot.selfMac;
    final color = blocked
        ? AppColors.danger
        : host.active
        ? AppColors.accent
        : AppColors.textMuted;
    final details = host.active
        ? [if (host.ip.isNotEmpty) host.ip, ?host.rate].join('  ·  ')
        : host.mac;

    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _showDetails(context),
      child: Row(
        children: [
          IconTile(icon: deviceIcon(host), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 8),
          if (busyMac == host.mac)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (isSelf)
            const StatusChip(label: 'جهازك', color: AppColors.accent)
          else if (blocked)
            const StatusChip(label: 'محظور', color: AppColors.danger)
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final cubit = context.read<DevicesCubit>();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _HostSheet(host: host, snapshot: snapshot, busyMac: busyMac),
      ),
    );
  }
}

class _HostSheet extends StatelessWidget {
  const _HostSheet({required this.host, required this.snapshot, this.busyMac});

  final Host host;
  final RouterSnapshot snapshot;
  final String? busyMac;

  @override
  Widget build(BuildContext context) {
    final blocked = snapshot.isBlocked(host);
    final isSelf = host.mac == snapshot.selfMac;
    final canAct = !isSelf && snapshot.filterFor(host) != null;
    final color = blocked ? AppColors.danger : AppColors.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(icon: deviceIcon(host), color: color, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        host.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        blocked
                            ? 'محظور'
                            : host.active
                            ? 'متصل دلوقتي'
                            : 'غير متصل',
                        style: TextStyle(
                          color: blocked || host.active
                              ? color
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (host.canRename)
                  IconButton(
                    tooltip: 'تغيير الاسم',
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.textMuted,
                    ),
                    onPressed: busyMac == null ? () => _rename(context) : null,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (host.active && host.ip.isNotEmpty)
              _DetailRow(label: 'عنوان IP', value: host.ip),
            _DetailRow(label: 'عنوان MAC', value: host.mac),
            if (host.active && host.rate != null)
              _DetailRow(label: 'سرعة الاتصال', value: host.rate!),
            _DetailRow(label: 'الشبكة', value: _networkName),
            const SizedBox(height: 16),
            if (isSelf)
              const Text(
                'ده الجهاز اللي بتستخدمه، فمينفعش يتحظر.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              )
            else if (canAct)
              _actionButton(context, blocked: blocked)
            else
              const Text(
                'الحظر بيشتغل على أجهزة الواي فاي بس.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            if (host.canForget && !blocked) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: busyMac == null ? () => _forget(context) : null,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textMuted,
                ),
                label: const Text(
                  'حذف من القائمة',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _networkName => snapshot.filterFor(host)?.ssid ?? host.interface;

  Widget _actionButton(BuildContext context, {required bool blocked}) {
    final enabled = busyMac == null;
    if (blocked) {
      return FilledButton.icon(
        onPressed: enabled ? () => _unblock(context) : null,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('فك الحظر'),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.danger,
        foregroundColor: const Color(0xFF2A0A12),
      ),
      onPressed: enabled ? () => _block(context) : null,
      icon: const Icon(Icons.block_rounded),
      label: const Text('حظر الجهاز'),
    );
  }

  Future<void> _block(BuildContext context) async {
    final cubit = context.read<DevicesCubit>();
    final navigator = Navigator.of(context);
    final plan = cubit.previewBlock(host);
    navigator.pop();
    if (plan == null) {
      return;
    }
    final confirmed = await showConfirm(
      navigator.context,
      title: 'حظر ${host.displayName}؟',
      body: _blockWarning(snapshot, host, plan),
      action: 'حظر',
      danger: true,
    );
    if (confirmed) {
      await cubit.block(host, plan);
    }
  }

  Future<void> _forget(BuildContext context) async {
    final cubit = context.read<DevicesCubit>();
    final navigator = Navigator.of(context);
    navigator.pop();
    final confirmed = await showConfirm(
      navigator.context,
      title: 'حذف ${host.displayName}؟',
      body:
          'الجهاز هيتشال من القائمة واسمه هيتمسح، بس ده مش حظر: لو اتصل تاني '
          'هيظهر كجهاز جديد.',
      action: 'حذف',
      danger: true,
    );
    if (confirmed) {
      await cubit.forget(host);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<DevicesCubit>();
    final navigator = Navigator.of(context);
    navigator.pop();
    final name = await showDialog<String>(
      context: navigator.context,
      builder: (_) => _RenameDialog(initial: host.displayName),
    );
    if (name != null && name != host.name) {
      await cubit.rename(host, name);
    }
  }

  Future<void> _unblock(BuildContext context) async {
    final cubit = context.read<DevicesCubit>();
    final navigator = Navigator.of(context);
    navigator.pop();
    final confirmed = await showConfirm(
      navigator.context,
      title: 'فك حظر ${host.displayName}؟',
      body: 'الشبكة ممكن تقطع ثواني على كل الأجهزة وقت تطبيق التغيير.',
      action: 'فك الحظر',
    );
    if (confirmed) {
      await cubit.unblock(host);
    }
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _input = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _input.text.trim();
    if (name.isNotEmpty) {
      Navigator.pop(context, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'تغيير اسم الجهاز',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _input,
        autofocus: true,
        maxLength: 64,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
