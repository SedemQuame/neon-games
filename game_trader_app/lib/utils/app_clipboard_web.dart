import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<bool> copyTextToClipboard(String value) async {
  try {
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement
          ..value = value;
    textArea.setAttribute('readonly', 'readonly');
    textArea.style.position = 'fixed';
    textArea.style.left = '-9999px';
    textArea.style.top = '0';
    textArea.style.opacity = '0';
    web.document.body?.appendChild(textArea);
    textArea.focus();
    textArea.select();
    final copied = web.document.execCommand('copy');
    textArea.remove();
    if (copied) {
      return true;
    }
  } catch (_) {
    // Continue to platform fallbacks below.
  }

  try {
    await web.window.navigator.clipboard.writeText(value).toDart;
    return true;
  } catch (_) {
    // Continue to Flutter fallback below.
  }

  try {
    await Clipboard.setData(ClipboardData(text: value));
    return true;
  } catch (_) {
    return false;
  }
}
