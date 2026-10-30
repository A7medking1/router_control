import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'devices_cubit.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Phase { opening, open, closing, failed }

/// Opens allow-only mode for a few minutes so a new device can join, then
/// turns it back on with the devices picked here added to the list.
class PairDevicePage extends StatefulWidget {
  const PairDevicePage({super.key});

  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  static const _windowSeconds = 180;
  static const _refreshEverySeconds = 6;

  _Phase _phase = _Phase.opening;
  late final Set<String> _allowed;
  final Set<String> _picked = {};
  Timer? _timer;
  int _remaining = _windowSeconds;

  DevicesCubit get _cubit => context.read<DevicesCubit>();

  @override
  void initState() {
    super.initState();
    _allowed = _cubit.state.snapshot!.mainFilter!.macs.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final opened = await _cubit.disableAllowOnly();
    if (!mounted) {
      return;
    }
    if (!opened) {
      Navigator.pop(context);
      return;
    }
    setState(() => _phase = _Phase.open);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    setState(() => _remaining--);
    if (_remaining <= 0) {
      _finish();
    } else if (_remaining % _refreshEverySeconds == 0) {
      _cubit.refresh(silent: true);
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    setState(() => _phase = _Phase.closing);
    // The router handles one request at a time.
    while (_cubit.state.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final closed = await _cubit.enableAllowOnly({..._allowed, ..._picked});
    if (!mounted) {
      return;
    }
    if (closed) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DevicesCubit>().state;
    final candidates = (state.snapshot?.hosts ?? const [])
        .where(
          (host) =>
              host.active && host.isWireless && !_allowed.contains(host.mac),
        )
        .toList();
    final working = _phase == _Phase.opening || _phase == _Phase.closing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.open) {
          _finish();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('ربط جهاز جديد'),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _StatusCard(phase: _phase, remaining: _remaining),
                  if (_phase == _Phase.open) ...[
                    const SectionLabel('خطوات الربط'),
                    const _Steps(),
                    SectionLabel('أجهزة جديدة', count: candidates.length),
                    if (candidates.isEmpty) const _Waiting(),
                    for (final host in candidates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          borderColor: _picked.contains(host.mac)
                              ? AppColors.accent.withValues(alpha: 0.4)
                              : AppColors.border,
                          onTap: () => setState(() {
                            if (!_picked.remove(host.mac)) {
                              _picked.add(host.mac);
                            }
                          }),
                          child: Row(
                            children: [
                              IconTile(
                                icon: deviceIcon(host),
                                color: AppColors.accent,
                                size: 42,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      host.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
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
                              Icon(
                                _picked.contains(host.mac)
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: _picked.contains(host.mac)
                                    ? AppColors.accent
                                    : AppColors.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: working ? null : _finish,
                    child: working
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_buttonLabel),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _buttonLabel {
    if (_phase == _Phase.failed) {
      return 'إعادة تشغيل الحماية';
    }
    return _picked.isEmpty
        ? 'إلغاء وتشغيل الحماية'
        : 'سماح لـ ${_picked.length} وتشغيل الحماية';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.phase, required this.remaining});

  final _Phase phase;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final failed = phase == _Phase.failed;
    final color = failed ? AppColors.danger : AppColors.warning;
    final minutes = remaining ~/ 60;
    final seconds = '${remaining % 60}'.padLeft(2, '0');
    final (title, body) = switch (phase) {
      _Phase.opening => ('بفتح الشبكة…', 'الواي فاي ممكن يقطع ثواني.'),
      _Phase.open => (
        'الشبكة مفتوحة',
        'أي جهاز معاه الباسورد يقدر يتصل دلوقتي. خليك في الشاشة دي.',
      ),
      _Phase.closing => ('بشغل الحماية…', 'الواي فاي ممكن يقطع ثواني.'),
      _Phase.failed => (
        'الحماية لسه مقفولة',
        'الراوتر ما استجابش. اتأكد إنك متصل بالواي فاي وجرب تاني.',
      ),
    };
    return AppCard(
      borderColor: color.withValues(alpha: 0.3),
      child: Row(
        children: [
          IconTile(
            icon: failed ? Icons.gpp_bad_rounded : Icons.lock_open_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (phase == _Phase.open) ...[
            const SizedBox(width: 8),
            Text(
              '$minutes:$seconds',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'افتح الواي فاي على الجهاز الجديد واتصل بالشبكة.',
      'استنى لحد ما يظهر في القائمة تحت.',
      'اختاره، واضغط الزرار اللي تحت.',
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, step) in steps.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(height: 12),
          Text(
            'بدور على أجهزة جديدة…',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
