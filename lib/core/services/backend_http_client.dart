import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as inner;

export 'package:http/http.dart'
    show
        BaseClient,
        BaseRequest,
        ByteStream,
        Client,
        MultipartFile,
        MultipartRequest,
        Request,
        Response,
        StreamedResponse;

const Duration _defaultTimeout = Duration(seconds: 15);
const int _gzipThresholdBytes = 1024;
const List<Duration> _retryBackoff = <Duration>[
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
];
const Set<int> _retryableStatusCodes = <int>{429, 502, 503, 504};

final inner.Client _client = inner.Client();
final Random _random = Random();

bool get isSlowLinkAndroid => !kIsWeb && Platform.isAndroid;

Future<inner.Response> get(
  Uri url, {
  Map<String, String>? headers,
}) {
  return _send(
    'GET',
    url,
    headers: headers,
  );
}

Future<inner.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _send(
    'POST',
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );
}

Future<inner.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _send(
    'PUT',
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );
}

Future<inner.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _send(
    'DELETE',
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );
}

Future<inner.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _send(
    'PATCH',
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );
}

Future<inner.Response> sendJson(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Object? jsonBody,
}) {
  final mergedHeaders = <String, String>{
    'Content-Type': 'application/json',
    if (headers != null) ...headers,
  };

  return _send(
    method,
    url,
    headers: mergedHeaders,
    body: jsonBody == null ? null : json.encode(jsonBody),
  );
}

Future<inner.Response> _send(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  final requestEncoding = encoding ?? utf8;
  final requestHeaders = <String, String>{if (headers != null) ...headers};
  final shouldUseSlowLink = isSlowLinkAndroid;

  if (shouldUseSlowLink) {
    requestHeaders.putIfAbsent('Accept', () => 'application/json');
    requestHeaders['Accept-Encoding'] = 'gzip';
    requestHeaders['X-Client-Platform'] = 'android';
    requestHeaders['X-Network-Profile'] = 'slow-link';

    await _ensureConnectivity();

    if (_shouldAttachIdempotencyKey(method, url, requestHeaders)) {
      requestHeaders.putIfAbsent('Idempotency-Key', _generateIdempotencyKey);
    }
  }

  final encodedBody = _encodeBody(
    method: method,
    url: url,
    headers: requestHeaders,
    body: body,
    encoding: requestEncoding,
    shouldUseSlowLink: shouldUseSlowLink,
  );

  final allowRetry = _shouldRetry(method, url, requestHeaders, shouldUseSlowLink);
  final maxAttempts = allowRetry ? 3 : 1;
  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final response = await _sendOnce(
        method,
        url,
        headers: requestHeaders,
        body: encodedBody,
      ).timeout(_defaultTimeout);

      if (!_shouldRetryStatusCode(response.statusCode) || attempt == maxAttempts) {
        return response;
      }
    } on TimeoutException catch (error) {
      lastError = error;
      if (attempt == maxAttempts) rethrow;
    } on SocketException catch (error) {
      lastError = error;
      if (attempt == maxAttempts) rethrow;
    } on HttpException catch (error) {
      lastError = error;
      if (attempt == maxAttempts) rethrow;
    }

    await Future<void>.delayed(_retryDelay(attempt));
  }

  if (lastError is Exception) {
    throw lastError;
  }

  throw TimeoutException('Request failed for ${url.path}');
}

Future<inner.Response> _sendOnce(
  String method,
  Uri url, {
  required Map<String, String> headers,
  required _EncodedBody body,
}) async {
  final request = inner.Request(method, url);
  request.headers.addAll(headers);

  if (body.bytes != null) {
    request.bodyBytes = body.bytes!;
  }

  final streamed = await _client.send(request);
  return inner.Response.fromStream(streamed);
}

_EncodedBody _encodeBody({
  required String method,
  required Uri url,
  required Map<String, String> headers,
  required Object? body,
  required Encoding encoding,
  required bool shouldUseSlowLink,
}) {
  if (body == null || method == 'GET') {
    return const _EncodedBody();
  }

  List<int> bytes;

  if (body is List<int>) {
    bytes = body;
  } else if (body is String) {
    bytes = encoding.encode(body);
  } else if (body is Map<String, String>) {
    final bodyString = body.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    headers.putIfAbsent(
      'Content-Type',
      () => 'application/x-www-form-urlencoded; charset=${encoding.name}',
    );
    bytes = encoding.encode(bodyString);
  } else {
    bytes = encoding.encode(body.toString());
  }

  if (shouldUseSlowLink &&
      _isJsonRequest(headers) &&
      bytes.length > _gzipThresholdBytes) {
    headers['Content-Encoding'] = 'gzip';
    bytes = gzip.encode(bytes);
  }

  return _EncodedBody(bytes: bytes);
}

bool _shouldRetry(
  String method,
  Uri url,
  Map<String, String> headers,
  bool shouldUseSlowLink,
) {
  if (!shouldUseSlowLink || _isSensitivePath(url.path)) {
    return false;
  }

  if (method == 'GET') {
    return true;
  }

  return headers.containsKey('Idempotency-Key');
}

bool _shouldAttachIdempotencyKey(
  String method,
  Uri url,
  Map<String, String> headers,
) {
  if (method == 'GET' || _isSensitivePath(url.path)) {
    return false;
  }

  if (!_isJsonRequest(headers)) {
    return false;
  }

  return true;
}

bool _isJsonRequest(Map<String, String> headers) {
  final contentType = headers.entries
      .firstWhere(
        (entry) => entry.key.toLowerCase() == 'content-type',
        orElse: () => const MapEntry('', ''),
      )
      .value
      .toLowerCase();

  return contentType.contains('application/json');
}

bool _shouldRetryStatusCode(int statusCode) =>
    _retryableStatusCodes.contains(statusCode);

bool _isSensitivePath(String path) {
  final normalizedPath = path.toLowerCase();
  return normalizedPath.contains('/auth/login') ||
      normalizedPath.contains('/auth/logout') ||
      normalizedPath.contains('password') ||
      normalizedPath.contains('/verify-direct-entry-password');
}

Future<void> _ensureConnectivity() async {
  final connectivity = await Connectivity().checkConnectivity();
  if (connectivity == ConnectivityResult.none) {
    throw SocketException('No network connection');
  }
}

Duration _retryDelay(int attempt) {
  final baseDelay = _retryBackoff[min(attempt - 1, _retryBackoff.length - 1)];
  return baseDelay + Duration(milliseconds: _random.nextInt(200));
}

String _generateIdempotencyKey() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final randomPart = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return 'android-$timestamp-$randomPart';
}

class _EncodedBody {
  const _EncodedBody({this.bytes});

  final List<int>? bytes;
}
