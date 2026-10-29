import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/format.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  final String code;
  const ApiException(this.message, {this.status = 0, this.code = ''});
  @override
  String toString() => message;
}

class ApiClient {
  static const sharedBaseUrl =
      'https://nguyen-hoai-nam-2380601398-api.onrender.com/v1';
  final http.Client client;
  String baseUrl = '';
  String? token;
  void Function()? onExpired;
  Future<bool> Function()? onRefresh;
  bool get isShared => Uri.tryParse(baseUrl)?.path == '/v1';
  ApiClient({http.Client? client}) : client = client ?? http.Client();
  static String validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/', '/v1', '/v1/'].contains(uri.path) ||
        [
          'localhost',
          '127.0.0.1',
          '0.0.0.0',
          '::1',
        ].contains(uri.host.toLowerCase()) ||
        uri.host.startsWith('127.') ||
        uri.host.endsWith('.localhost')) {
      throw const ApiException(
        'Nhập URL HTTPS công khai, chỉ cho phép tiền tố /v1 và không kèm thông tin đăng nhập.',
      );
    }
    final normalized = value.trim().replaceFirst(RegExp(r'/$'), '');
    if (uri.host == 'nguyen-hoai-nam-2380601398-api.onrender.com' &&
        ['', '/'].contains(uri.path)) {
      return '$normalized/v1';
    }
    return normalized;
  }

  Future<dynamic> request(
    String method,
    String path, [
    Json? body,
    bool retried = false,
  ]) async {
    if (baseUrl.isEmpty) {
      throw const ApiException('Chưa cấu hình địa chỉ API HTTPS.');
    }
    final sentToken = token;
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final req = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final response = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 75));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw ApiException(
          'Máy chủ trả dữ liệu không hợp lệ (${response.statusCode}).',
          status: response.statusCode,
        );
      }
      if (response.statusCode >= 400) {
        final error = decoded is Map ? decoded['error'] : null;
        final protected = !path.startsWith('/auth/');
        if (response.statusCode == 401 &&
            token != null &&
            isShared &&
            protected &&
            !retried) {
          if ((token != sentToken) || (await onRefresh?.call() ?? false)) {
            return await request(method, path, body, true);
          }
        }
        if (response.statusCode == 401 &&
            token != null &&
            (!isShared || protected)) {
          onExpired?.call();
        }
        var message = error is Map
            ? error['message']?.toString() ?? 'Yêu cầu thất bại.'
            : 'Yêu cầu thất bại.';
        if (error is Map && error['details'] is List) {
          message +=
              '\n${(error['details'] as List).map((d) => '${d['field']}: ${d['message']}').join('\n')}';
        }
        throw ApiException(
          message,
          status: response.statusCode,
          code: error is Map ? error['code']?.toString() ?? '' : '',
        );
      }
      if (decoded is! Map || !decoded.containsKey('data')) {
        throw const ApiException('Phản hồi API thiếu dữ liệu.');
      }
      return decoded['data'];
    } on TimeoutException {
      throw const ApiException(
        'Kết nối quá thời gian. Render có thể đang khởi động; hãy thử lại.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ API.',
      );
    }
  }

  Future<Json> get(String path) async =>
      Map<String, dynamic>.from(await request('GET', path) as Map);
  Future<List<Json>> list(String path) async =>
      (await request('GET', path) as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<Json> post(String path, Json body) async =>
      Map<String, dynamic>.from(await request('POST', path, body) as Map);
  Future<Json> put(String path, Json body) async =>
      Map<String, dynamic>.from(await request('PUT', path, body) as Map);
  Future<Json> patch(String path, Json body) async =>
      Map<String, dynamic>.from(await request('PATCH', path, body) as Map);
  Future<void> delete(String path) async {
    await request('DELETE', path);
  }
}
