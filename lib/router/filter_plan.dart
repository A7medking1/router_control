import 'models.dart';

class FilterPlanException implements Exception {
  const FilterPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FilterPlan {
  const FilterPlan(this.next, {this.replacesStoredList = false});

  final WlanFilter next;

  /// True when the router's stored list is thrown away. That list has another
  /// meaning under the current policy and must not be reused for blocking.
  final bool replacesStoredList;
}

FilterPlan planBlock(WlanFilter filter, String mac, {String? selfMac}) {
  final target = normalizeMac(mac);
  if (selfMac != null && normalizeMac(selfMac) == target) {
    throw const FilterPlanException('ده الجهاز اللي بتستخدمه، مينفعش تحظره');
  }
  if (filter.isAllowOnly) {
    throw const FilterPlanException(
      'وضع "المسموح لهم بس" شغال، قفله من صفحة الراوتر الأول',
    );
  }
  if (!filter.isBlocking) {
    return FilterPlan(
      filter.copyWith(
        enabled: true,
        policy: WlanFilter.policyBlock,
        macs: [target],
      ),
      replacesStoredList: filter.macs.isNotEmpty,
    );
  }
  if (filter.macs.contains(target)) {
    return FilterPlan(filter);
  }
  if (filter.macs.length >= WlanFilter.maxMacs) {
    throw const FilterPlanException('الراوتر بيقبل 32 جهاز بس في القائمة');
  }
  return FilterPlan(filter.copyWith(macs: [...filter.macs, target]));
}

FilterPlan planUnblock(WlanFilter filter, String mac) {
  final target = normalizeMac(mac);
  if (!filter.blocks(target)) {
    return FilterPlan(filter);
  }
  final remaining = filter.macs.where((item) => item != target).toList();
  return FilterPlan(
    filter.copyWith(enabled: remaining.isNotEmpty, macs: remaining),
  );
}

/// [selfMac] is required: without it the app could lock out its own device.
FilterPlan planAllowOnly(
  WlanFilter filter,
  Iterable<String> macs, {
  required String? selfMac,
}) {
  if (selfMac == null) {
    throw const FilterPlanException(
      'مش قادر أحدد جهازك في الشبكة، حدث القائمة وجرب تاني',
    );
  }
  final selected = {normalizeMac(selfMac), ...macs.map(normalizeMac)};
  if (selected.length > WlanFilter.maxMacs) {
    throw const FilterPlanException('الراوتر بيقبل 32 جهاز بس في القائمة');
  }
  return FilterPlan(
    filter.copyWith(
      enabled: true,
      policy: WlanFilter.policyAllowOnly,
      macs: selected.toList(),
    ),
    replacesStoredList:
        filter.macs.isNotEmpty && !selected.containsAll(filter.macs),
  );
}

FilterPlan planDisableAllowOnly(WlanFilter filter) =>
    FilterPlan(filter.isAllowOnly ? filter.copyWith(enabled: false) : filter);

/// Reduces user input to a bare domain, or null when it is not one.
String? normalizeDomain(String input) {
  var value = input.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
  value = value.split(RegExp(r'[/?#]')).first;
  final valid = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(value);
  return valid && value.length <= 255 ? value : null;
}
