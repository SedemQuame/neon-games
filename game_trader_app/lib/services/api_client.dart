import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';

class ApiClient {
  ApiClient({String? baseUrl})
    : baseUrl = _normalizeBase(
        baseUrl ??
            const String.fromEnvironment(
              'GAMEHUB_BASE_URL',
              defaultValue: 'http://127.0.0.1',
            ),
      );

  final String baseUrl;
  final http.Client _client = http.Client();

  Uri _buildUri(String path, [Map<String, dynamic>? query]) {
    final normalizedPath = path.startsWith('/')
        ? path
        : '/$path'; // ensure leading slash
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...query.map((key, value) => MapEntry(key, value.toString())),
      },
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    String? token,
  }) async {
    final uri = _buildUri(path, query);
    final started = DateTime.now();
    _log('GET $uri');
    final response = await _client.get(uri, headers: _headers(token));
    _logResponse('GET', uri, response.statusCode, started);
    return _handleResponse(response);
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = _buildUri(path);
    final started = DateTime.now();
    _log('POST $uri');
    final response = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body ?? const <String, dynamic>{}),
    );
    _logResponse('POST', uri, response.statusCode, started);
    return _handleResponse(response);
  }

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return const <String, dynamic>{};
      }
      return jsonDecode(response.body);
    }
    final uri = response.request?.url;
    final serverMessage = _extractError(response.body);
    final message = _friendlyErrorMessage(response.statusCode, serverMessage);
    AppLogger.instance.log(
      'api',
      'HTTP ${response.statusCode} ${uri ?? ''} -> $serverMessage',
      level: LogLevel.error,
    );
    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      uri: uri,
    );
  }

  String _extractError(String rawBody) {
    if (rawBody.isEmpty) {
      return 'Unexpected error';
    }
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
      return rawBody;
    } catch (_) {
      return rawBody;
    }
  }

  String _friendlyErrorMessage(int statusCode, String serverMessage) {
    final trimmed = serverMessage.trim();
    final fallback =
        "We're having trouble reaching GameHub right now. Please try again in a moment.";
    final looksHtml = _looksLikeHtml(trimmed);
    if (statusCode >= 500 || looksHtml || trimmed.isEmpty) {
      return fallback;
    }
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }

  bool _looksLikeHtml(String input) {
    final lower = input.toLowerCase();
    return lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.contains('<body');
  }

  void close() => _client.close();

  String get websocketBase {
    if (baseUrl.startsWith('https')) {
      return baseUrl.replaceFirst('https', 'wss');
    }
    return baseUrl.replaceFirst('http', 'ws');
  }

  static String _normalizeBase(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  void _logResponse(String method, Uri uri, int status, DateTime started) {
    final elapsed = DateTime.now().difference(started);
    _log('$method ${uri.path} -> $status (${elapsed.inMilliseconds}ms)');
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[ApiClient] $message');
    }
    AppLogger.instance.log('api', message, level: LogLevel.debug);
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.statusCode,
    this.uri,
  });

  final String message;
  final int statusCode;
  final Uri? uri;

  @override
  String toString() =>
      'ApiException($statusCode): $message${uri != null ? ' [$uri]' : ''}';
}
