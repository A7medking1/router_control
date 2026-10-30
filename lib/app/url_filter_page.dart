import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../router/filter_plan.dart';
import '../router/models.dart';
import '../router/router_client.dart';
import '../router/router_repository.dart';
import 'theme.dart';
import 'widgets.dart';

class UrlFilterPage extends StatefulWidget {
  const UrlFilterPage({super.key});

  @override
  State<UrlFilterPage> createState() => _UrlFilterPageState();
}

class _UrlFilterPageState extends State<UrlFilterPage> {
  final _input = TextEditingController();
  List<UrlRule>? _rules;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run(() async {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Runs one router change, then reloads. Requests are never sent in parallel.
  Future<bool> _run(Future<void> Function() action) async {
    final repository = context.read<RouterRepository>();
    setState(() => _busy = true);
    var succeeded = false;
    try {
      await action();
      final rules = await repository.loadUrlRules();
      succeeded = true;
      if (mounted) {
        setState(() => _rules = rules);
      }
    } on Exception catch (error) {
      if (mounted) {
        showError(
          context,
          error is RouterException
              ? error.message
              : 'الاتصال بالراوتر فشل، جرب تاني',
        );
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
    return succeeded;
  }

  Future<void> _add() async {
    final domain = normalizeDomain(_input.text);
    if (domain == null) {
      showError(context, 'اكتب دومين صحيح زي example.com');
      return;
    }
    final repository = context.read<RouterRepository>();
    if (await _run(() => repository.addUrlRule(domain))) {
      _input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return Scaffold(
      appBar: AppBar(title: const Text('حجب المواقع')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'حجب موقع جديد',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 2),
                const Text(
                  'الحجب بيتطبق على كل الأجهزة في الشبكة',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _input,
                  enabled: !_busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'example.com',
                    prefixIcon: Icon(Icons.language_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: const Text('حجب الموقع'),
                ),
              ],
            ),
          ),
          SectionLabel('المواقع المحجوبة', count: rules?.length),
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          if (rules != null && rules.isEmpty) const _EmptyRules(),
          for (final rule in rules ?? const <UrlRule>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
                child: Row(
                  children: [
                    const IconTile(
                      icon: Icons.public_off_rounded,
                      color: AppColors.danger,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        rule.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إلغاء الحجب',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _busy
                          ? null
                          : () {
                              final repository = context
                                  .read<RouterRepository>();
                              _run(() => repository.deleteUrlRule(rule));
                            },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyRules extends StatelessWidget {
  const _EmptyRules();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          IconTile(
            icon: Icons.shield_outlined,
            color: AppColors.textMuted,
            size: 58,
          ),
          SizedBox(height: 12),
          Text(
            'مفيش مواقع محجوبة',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
