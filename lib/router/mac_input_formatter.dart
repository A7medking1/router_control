import 'package:flutter/services.dart';

const macTextLength = 17;

/// Keeps hex digits only, uppercases them and places the colons. A trailing
/// colon is added only while typing forward, so backspace is not undone.
class MacInputFormatter extends TextInputFormatter {
  const MacInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var hex = newValue.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length > 12) {
      hex = hex.substring(0, 12);
    }
    final pairs = [
      for (var i = 0; i < hex.length; i += 2)
        hex.substring(i, i + 2 > hex.length ? hex.length : i + 2),
    ];
    var text = pairs.join(':');
    final typing = newValue.text.length > oldValue.text.length;
    if (typing && hex.isNotEmpty && hex.length.isEven && hex.length < 12) {
      text += ':';
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
