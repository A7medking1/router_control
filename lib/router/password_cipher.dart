import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Matches the router page's `enc()`: base64 of the password, RSA PKCS#1 v1.5,
/// hex encoded to the modulus length.
String encryptPassword(
  String password,
  String modulusHex,
  String exponentHex, {
  Random? random,
}) {
  final rng = random ?? Random.secure();
  final modulus = BigInt.parse(modulusHex, radix: 16);
  final exponent = BigInt.parse(exponentHex, radix: 16);
  final message = ascii.encode(base64.encode(utf8.encode(password)));
  final size = (modulus.bitLength + 7) >> 3;
  if (message.length > size - 11) {
    throw ArgumentError('Password is too long');
  }

  final block = Uint8List(size);
  block[1] = 2;
  final paddingEnd = size - message.length - 1;
  for (var i = 2; i < paddingEnd; i++) {
    block[i] = rng.nextInt(255) + 1;
  }
  block.setRange(paddingEnd + 1, size, message);

  var value = BigInt.zero;
  for (final byte in block) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value
      .modPow(exponent, modulus)
      .toRadixString(16)
      .padLeft(size * 2, '0');
}
