import 'package:equatable/equatable.dart';

String normalizeMac(String mac) => mac.trim().toUpperCase();

/// Accepts ":" or "-" separators. Returns null for anything a Wi-Fi client
/// cannot use: malformed, all zeros, or a multicast/broadcast address.
String? parseMac(String input) {
  final mac = normalizeMac(input).replaceAll('-', ':');
  if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
    return null;
  }
  final isMulticast = int.parse(mac.substring(0, 2), radix: 16).isOdd;
  return isMulticast || mac == '00:00:00:00:00:00' ? null : mac;
}

class Host extends Equatable {
  const Host({
    required this.mac,
    required this.ip,
    required this.name,
    required this.interface,
    required this.active,
    this.rate,
    this.rssi,
    this.raw = const {},
  });

  /// An address on a filter list that the router has no device entry for.
  factory Host.listed(String mac, String interface) =>
      Host(mac: mac, ip: '', name: mac, interface: interface, active: false);

  factory Host.fromJson(Map<String, dynamic> json) {
    final mac = normalizeMac('${json['MACAddress'] ?? ''}');
    final actualName = '${json['ActualName'] ?? ''}';
    final hostName = '${json['HostName'] ?? ''}';
    return Host(
      mac: mac,
      ip: '${json['IPAddress'] ?? ''}'.trim(),
      name: actualName.isNotEmpty
          ? actualName
          : hostName.isNotEmpty
          ? hostName
          : mac,
      interface: '${json['Layer2Interface'] ?? ''}',
      active: json['Active'] == true,
      rate: json['AssociatedDeviceRate'] as String?,
      rssi: json['Rssi']?.toString(),
      raw: json,
    );
  }

  final String mac;
  final String ip;
  final String name;
  final String interface;
  final bool active;
  final String? rate;
  final String? rssi;
  final Map<String, dynamic> raw;

  bool get canRename => raw.isNotEmpty;

  /// The router's page disables delete while a device is connected.
  bool get canForget => canRename && !active && raw['Active46'] != true;

  Map<String, dynamic> toForgetJson() => {'ID': raw['ID'], 'MACAddress': mac};

  /// Body of POST system/HostInfo. The router's page sends the whole entry.
  Map<String, dynamic> toRenameJson(String newName) => {
    ...raw,
    'ActualName': newName,
  };

  bool get isWireless => interface.startsWith('SSID');

  /// The router appends "-Wireless" and falls back to raw MAC fragments.
  String get displayName {
    final clean = name.replaceFirst(
      RegExp(r'-Wireless(-[0-9A-Fa-f]{2})?$'),
      '',
    );
    final isMacLike = RegExp(r'^([0-9A-Fa-f]{2}[-:]){4,5}[0-9A-Fa-f]{2}$')
        .hasMatch(clean);
    if (!canRename && clean == mac) {
      return 'جهاز مضاف يدويًا';
    }
    return isMacLike ? 'جهاز غير معروف' : clean;
  }

  @override
  List<Object?> get props => [mac, ip, name, interface, active, rate, rssi];
}

/// Wi-Fi MAC filter of one SSID. The router keeps a single address list and
/// [policy] decides what it means: 0 blocks the listed devices, 1 allows only
/// the listed devices.
class WlanFilter extends Equatable {
  const WlanFilter({
    required this.id,
    required this.name,
    required this.ssid,
    required this.band,
    required this.enabled,
    required this.policy,
    required this.macs,
  });

  factory WlanFilter.fromJson(Map<String, dynamic> json) => WlanFilter(
    id: '${json['ID']}',
    name: '${json['Name'] ?? ''}',
    ssid: '${json['SSID'] ?? ''}',
    band: '${json['FrequencyBand'] ?? ''}',
    enabled: json['MACAddressControlEnabled'] == true,
    policy: json['MacFilterPolicy'] as int? ?? policyAllowOnly,
    macs: [
      for (final item in json['MACAddresses'] as List? ?? const [])
        normalizeMac('${(item as Map)['MACAddress']}'),
    ],
  );

  static const policyBlock = 0;
  static const policyAllowOnly = 1;
  static const maxMacs = 32;

  final String id;
  final String name;
  final String ssid;
  final String band;
  final bool enabled;
  final int policy;
  final List<String> macs;

  bool get isBlocking => enabled && policy == policyBlock;
  bool get isAllowOnly => enabled && policy == policyAllowOnly;
  bool blocks(String mac) => isBlocking && macs.contains(normalizeMac(mac));

  WlanFilter copyWith({bool? enabled, int? policy, List<String>? macs}) =>
      WlanFilter(
        id: id,
        name: name,
        ssid: ssid,
        band: band,
        enabled: enabled ?? this.enabled,
        policy: policy ?? this.policy,
        macs: macs ?? this.macs,
      );

  /// Body of POST ntwk/wlanfilterone, as sent by the router's own page.
  Map<String, dynamic> toSubmitJson() => {
    'ID': id,
    'FrequencyBand': band,
    'MACAddressControlEnabled': enabled,
    'MacFilterPolicy': policy,
    'MacFilters': [
      for (final mac in macs) {'MACAddress': mac},
    ],
  };

  Map<String, dynamic> toBackupJson() => {
    'ID': id,
    'Name': name,
    'SSID': ssid,
    'FrequencyBand': band,
    'MACAddressControlEnabled': enabled,
    'MacFilterPolicy': policy,
    'MACAddresses': [
      for (final mac in macs) {'MACAddress': mac},
    ],
  };

  @override
  List<Object?> get props => [id, name, ssid, band, enabled, policy, macs];
}

class UrlRule extends Equatable {
  const UrlRule({required this.id, required this.url, required this.enabled});

  factory UrlRule.fromJson(Map<String, dynamic> json) => UrlRule(
    id: '${json['ID']}',
    url: Uri.decodeFull('${json['URL'] ?? ''}'),
    enabled: json['Status'] == 2,
  );

  final String id;
  final String url;
  final bool enabled;

  @override
  List<Object?> get props => [id, url, enabled];
}

class Traffic extends Equatable {
  const Traffic({required this.downloaded, required this.uploaded});

  /// Bytes the router sent to and received from Wi-Fi clients.
  final int downloaded;
  final int uploaded;

  @override
  List<Object?> get props => [downloaded, uploaded];
}
