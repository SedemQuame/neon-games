import 'app_clipboard_fallback.dart'
    if (dart.library.html) 'app_clipboard_web.dart'
    as platform;

Future<bool> copyTextToClipboard(String value) {
  return platform.copyTextToClipboard(value);
}
