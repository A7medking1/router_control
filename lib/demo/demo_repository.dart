import '../router/filter_plan.dart';
import '../router/models.dart';
import '../router/router_repository.dart';
import '../router/secure_store.dart';

/// Keeps nothing, so demo mode never reads or replaces saved credentials.
class _DemoStore extends SecureStore {
  const _DemoStore();

  @override
  Future<Credentials?> readCredentials() async => null;

  @override
  Future<void> saveCredentials(Credentials credentials) async {}

  @override
  Future<void> clearCredentials() async {}

  @override
  Future<void> backupFilterOnce(WlanFilter filter) async {}
}

/// Fake router for trying the app and taking screenshots without real data.
/// Enabled with `--dart-define=DEMO=true`.
class DemoRouterRepository extends RouterRepository {
  DemoRouterRepository() : super(store: const _DemoStore());

  static const _selfMac = '02:00:00:00:00:01';
  static const _guest = Host(
    mac: '02:00:00:00:00:99',
    ip: '192.168.1.40',
    name: 'Guest Phone',
    interface: 'SSID1',
    active: true,
    rate: '72 Mbps',
    raw: {'ID': 'demo.guest'},
  );

  WlanFilter _filter = const WlanFilter(
    id: 'demo.filter',
    name: 'SSID1',
    ssid: 'Home WiFi',
    band: '2.4GHz',
    enabled: true,
    policy: WlanFilter.policyBlock,
    macs: ['02:00:00:00:00:08'],
  );

  final List<Host> _hosts = [
    _host(1, 'MacBook-Pro', '192.168.1.2', active: true, rate: '130 Mbps'),
    _host(2, 'iPhone-15', '192.168.1.3', active: true, rate: '130 Mbps'),
    _host(3, 'Living-Room-TV', '192.168.1.4', active: true, rate: '104 Mbps'),
    _host(4, 'Galaxy-S24', '192.168.1.5', active: true, rate: '117 Mbps'),
    _host(5, 'iPad-Air', '192.168.1.6', active: true, rate: '78 Mbps'),
    _host(6, 'Office-Laptop', '192.168.1.7'),
    _host(7, 'Redmi-Note-13', '192.168.1.8'),
    _host(8, 'Unknown-Tablet', '192.168.1.9'),
  ];

  final List<UrlRule> _rules = [
    const UrlRule(id: 'demo.1', url: 'example.com', enabled: true),
    const UrlRule(id: 'demo.2', url: 'ads.example.net', enabled: true),
  ];

  static Host _host(
    int number,
    String name,
    String ip, {
    bool active = false,
    String? rate,
  }) {
    final mac = '02:00:00:00:00:${'$number'.padLeft(2, '0')}';
    return Host(
      mac: mac,
      ip: ip,
      name: name,
      interface: 'SSID1',
      active: active,
      rate: rate,
      raw: {'ID': 'demo.$number', 'MACAddress': mac, 'ActualName': name},
    );
  }

  @override
  Future<void> login(Credentials credentials, {required bool remember}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<RouterSnapshot> load() async {
    final filters = [_filter];
    final pairing = !_filter.enabled && _filter.macs.isNotEmpty;
    return RouterSnapshot(
      hosts: withListedHosts([..._hosts, if (pairing) _guest], filters),
      filters: filters,
      traffic: const Traffic(downloaded: 7985000000, uploaded: 1240000000),
      selfMac: _selfMac,
    );
  }

  @override
  Future<void> applyFilter(WlanFilter current, FilterPlan plan) async {
    _filter = plan.next;
  }

  @override
  Future<void> renameHost(Host host, String name) async {
    final index = _hosts.indexWhere((item) => item.mac == host.mac);
    _hosts[index] = Host(
      mac: host.mac,
      ip: host.ip,
      name: name,
      interface: host.interface,
      active: host.active,
      rate: host.rate,
      raw: host.raw,
    );
  }

  @override
  Future<void> forgetHost(Host host) async {
    _hosts.removeWhere((item) => item.mac == host.mac);
  }

  @override
  Future<List<UrlRule>> loadUrlRules() async => List.of(_rules);

  @override
  Future<void> addUrlRule(String domain) async {
    _rules.add(UrlRule(id: 'demo.$domain', url: domain, enabled: true));
  }

  @override
  Future<void> deleteUrlRule(UrlRule rule) async => _rules.remove(rule);
}
