import 'package:flutter/services.dart';

Future<bool> copyTextToClipboard(String value) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    return true;
  } catch (_) {
    return false;
  }
}
