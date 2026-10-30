import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:router_control/router/filter_plan.dart';
import 'package:router_control/router/mac_input_formatter.dart';
import 'package:router_control/router/models.dart';
import 'package:router_control/router/password_cipher.dart';
import 'package:router_control/router/router_client.dart';
import 'package:router_control/router/router_repository.dart';

const macA = 'AA:BB:CC:00:00:01';
const macB = 'AA:BB:CC:00:00:02';

WlanFilter filter({
  bool enabled = false,
  int policy = WlanFilter.policyAllowOnly,
  List<String> macs = const [],
}) => WlanFilter(
  id: 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.',
  name: 'SSID1',
  ssid: 'Home',
  band: '2.4GHz',
  enabled: enabled,
  policy: policy,
  macs: macs,
);

void main() {
  group('encryptPassword', () {
    test('decrypts back to the base64 password with PKCS#1 v1.5 padding', () {
      final p = BigInt.two.pow(521) - BigInt.one;
      final q = BigInt.two.pow(607) - BigInt.one;
      final n = p * q;
      final e = BigInt.from(65537);
      final d = e.modInverse((p - BigInt.one) * (q - BigInt.one));

      final cipher = encryptPassword('tést-pw', n.toRadixString(16), '010001');
      final size = (n.bitLength + 7) >> 3;
      expect(cipher.length, size * 2);

      final hex = BigInt.parse(
        cipher,
        radix: 16,
      ).modPow(d, n).toRadixString(16).padLeft(size * 2, '0');
      final block = [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      expect(block.sublist(0, 2), [0, 2]);
      final separator = block.indexOf(0, 2);
      expect(separator, greaterThanOrEqualTo(10));
      final decoded = base64.decode(ascii.decode(block.sublist(separator + 1)));
      expect(utf8.decode(decoded), 'tést-pw');
    });
  });

  test('unwrapResponse strips the router JSON guard', () {
    expect(unwrapResponse('while(1); /*{"a":1}*/\n'), '{"a":1}');
    expect(unwrapResponse('[1]'), '[1]');
  });

  group('planBlock', () {
    test('never reuses an allow-list as a block list', () {
      final plan = planBlock(filter(macs: [macA, 'AA:BB:CC:00:00:09']), macB);
      expect(plan.next.macs, [macB]);
      expect(plan.next.policy, WlanFilter.policyBlock);
      expect(plan.next.enabled, isTrue);
      expect(plan.replacesStoredList, isTrue);
    });

    test('adds to an active block list without replacing it', () {
      final plan = planBlock(
        filter(enabled: true, policy: WlanFilter.policyBlock, macs: [macA]),
        macB,
      );
      expect(plan.next.macs, [macA, macB]);
      expect(plan.replacesStoredList, isFalse);
    });

    test('refuses the current device, in any letter case', () {
      expect(
        () => planBlock(filter(), macA.toLowerCase(), selfMac: macA),
        throwsA(isA<FilterPlanException>()),
      );
    });

    test('refuses while allow-only mode is on', () {
      expect(
        () => planBlock(filter(enabled: true, macs: [macA]), macB),
        throwsA(isA<FilterPlanException>()),
      );
    });

    test('enforces the 32 address limit', () {
      final macs = [
        for (var i = 0; i < 32; i++)
          'AA:BB:CC:00:01:${i.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      ];
      expect(
        () => planBlock(
          filter(enabled: true, policy: WlanFilter.policyBlock, macs: macs),
          macA,
        ),
        throwsA(isA<FilterPlanException>()),
      );
    });
  });

  group('planUnblock', () {
    test('turns the filter off when the last device is removed', () {
      final plan = planUnblock(
        filter(enabled: true, policy: WlanFilter.policyBlock, macs: [macA]),
        macA,
      );
      expect(plan.next.enabled, isFalse);
      expect(plan.next.macs, isEmpty);
    });

    test('leaves an allow-list untouched', () {
      final current = filter(enabled: true, macs: [macA]);
      expect(planUnblock(current, macA).next, current);
    });
  });

  group('planAllowOnly', () {
    test('always keeps the current device in the list', () {
      final plan = planAllowOnly(filter(), [macB], selfMac: macA);
      expect(plan.next.macs, containsAll([macA, macB]));
      expect(plan.next.policy, WlanFilter.policyAllowOnly);
      expect(plan.next.enabled, isTrue);
    });

    test('refuses when the current device is unknown', () {
      expect(
        () => planAllowOnly(filter(), [macB], selfMac: null),
        throwsA(isA<FilterPlanException>()),
      );
    });

    test('flags dropped addresses so the old list gets backed up', () {
      final plan = planAllowOnly(filter(macs: ['AA:BB:CC:00:00:09']), [
        macB,
      ], selfMac: macA);
      expect(plan.replacesStoredList, isTrue);
    });

    test('enforces the 32 address limit including the current device', () {
      final macs = [
        for (var i = 0; i < 32; i++)
          'AA:BB:CC:00:01:${i.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      ];
      expect(
        () => planAllowOnly(filter(), macs, selfMac: macA),
        throwsA(isA<FilterPlanException>()),
      );
    });
  });

  test('planDisableAllowOnly keeps a block list running', () {
    final blocking = filter(
      enabled: true,
      policy: WlanFilter.policyBlock,
      macs: [macA],
    );
    expect(planDisableAllowOnly(blocking).next, blocking);
    expect(
      planDisableAllowOnly(filter(enabled: true, macs: [macA])).next.enabled,
      isFalse,
    );
  });

  test('normalizeDomain reduces input to a bare domain', () {
    expect(
      normalizeDomain(' https://Www.Example.com/a?b=1 '),
      'www.example.com',
    );
    expect(normalizeDomain('example.co.uk'), 'example.co.uk');
    expect(normalizeDomain('localhost'), isNull);
    expect(normalizeDomain('not a domain'), isNull);
    expect(normalizeDomain(''), isNull);
  });

  test('toSubmitJson matches the router page format', () {
    final json = filter(macs: [macA]).toSubmitJson();
    expect(json.keys, [
      'ID',
      'FrequencyBand',
      'MACAddressControlEnabled',
      'MacFilterPolicy',
      'MacFilters',
    ]);
    expect(json['MacFilters'], [
      {'MACAddress': macA},
    ]);
  });

  test('displayName hides router suffixes and raw MAC names', () {
    Host named(String name) =>
        Host(mac: macA, ip: '', name: name, interface: 'SSID1', active: true);
    expect(named('iPhone-Wireless').displayName, 'iPhone');
    expect(named('Galaxy-Tab-Wireless').displayName, 'Galaxy-Tab');
    expect(named('02-AA-BB-CC-DD-Wireless-42').displayName, 'جهاز غير معروف');
    expect(named('02-AA-BB-CC-DD-EE-Wireless').displayName, 'جهاز غير معروف');
  });

  test('parseMac normalizes input and rejects unusable addresses', () {
    expect(parseMac(' aa-bb-cc-00-00-02 '), 'AA:BB:CC:00:00:02');
    expect(parseMac('AA:BB:CC:00:00'), isNull);
    expect(parseMac('00:00:00:00:00:00'), isNull);
    expect(parseMac('FF:FF:FF:FF:FF:FF'), isNull);
    expect(parseMac('01:00:5E:00:00:01'), isNull);
  });

  test('toRenameJson keeps every router field and changes only the name', () {
    final host = Host.fromJson({
      'ID': 'InternetGatewayDevice.LANDevice.1.Hosts.Host.7.',
      'MACAddress': macA,
      'ActualName': 'Old',
      'HostName': 'phone',
      'Layer2Interface': 'SSID1',
    });
    final json = host.toRenameJson('New');
    expect(json['ActualName'], 'New');
    expect(json['ID'], host.raw['ID']);
    expect(json['HostName'], 'phone');
    expect(json.length, host.raw.length);
  });

  group('withListedHosts', () {
    final known = Host.fromJson({
      'MACAddress': macA,
      'Layer2Interface': 'SSID1',
    });

    test('shows active filter addresses the router does not know', () {
      final hosts = withListedHosts(
        [known],
        [
          filter(enabled: true, macs: [macA, macB]),
        ],
      );
      expect(hosts.map((h) => h.mac), [macA, macB]);
      expect(hosts.last.canRename, isFalse);
      expect(hosts.last.displayName, 'جهاز مضاف يدويًا');
      expect(hosts.last.interface, 'SSID1');
    });

    test('ignores the stored list while the filter is off', () {
      final hosts = withListedHosts(
        [known],
        [
          filter(macs: [macB]),
        ],
      );
      expect(hosts, [known]);
    });
  });

  group('MacInputFormatter', () {
    const formatter = MacInputFormatter();
    String type(String old, String text) => formatter
        .formatEditUpdate(
          TextEditingValue(text: old),
          TextEditingValue(text: text),
        )
        .text;

    test('adds a colon after each pair and uppercases', () {
      expect(type('', 'a'), 'A');
      expect(type('A', 'Ab'), 'AB:');
      expect(type('AB:', 'AB:1'), 'AB:1');
    });

    test('does not re-add a colon while deleting', () {
      expect(type('AB:C', 'AB:'), 'AB');
      expect(type('AB', 'A'), 'A');
    });

    test('drops other characters and stops at a full address', () {
      expect(type('', 'aa-bb-cc-11-22-33-44'), 'AA:BB:CC:11:22:33');
      expect(type('', 'zz'), '');
    });
  });

  test('only offline router entries can be forgotten', () {
    Host host({bool active = false, bool active46 = false}) => Host.fromJson({
      'ID': 'InternetGatewayDevice.LANDevice.1.Hosts.Host.7.',
      'MACAddress': macA,
      'Layer2Interface': 'SSID1',
      'Active': active,
      'Active46': active46,
    });
    expect(host().canForget, isTrue);
    expect(host(active: true).canForget, isFalse);
    expect(host(active46: true).canForget, isFalse);
    expect(Host.listed(macA, 'SSID1').canForget, isFalse);
    expect(host().toForgetJson(), {
      'ID': 'InternetGatewayDevice.LANDevice.1.Hosts.Host.7.',
      'MACAddress': macA,
    });
  });

  test('Host falls back to the MAC when the router has no name', () {
    final host = Host.fromJson({
      'MACAddress': 'aa:bb:cc:00:00:01',
      'ActualName': '',
      'HostName': '',
      'IPAddress': ' ',
      'Layer2Interface': 'SSID1',
      'Active': true,
    });
    expect(host.name, macA);
    expect(host.ip, '');
    expect(host.isWireless, isTrue);
  });
}
