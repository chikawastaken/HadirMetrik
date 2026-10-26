import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

const baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: kIsWeb ? 'http://localhost:8000/api/v1' : 'http://10.0.2.2:8000/api/v1',
);

class ApiError implements Exception {
  ApiError(this.message, [this.errors]);
  final String message;
  final Map<String, dynamic>? errors;
  @override
  String toString() => message;
}

class Api {
  static String? token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _handle(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError('Respons server tidak valid (${r.statusCode})');
    }
    if (r.statusCode >= 200 && r.statusCode < 300 && body['success'] == true) {
      return (body['data'] as Map<String, dynamic>?) ?? {};
    }
    throw ApiError(body['message'] ?? 'Terjadi kesalahan', body['errors']);
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async =>
      _handle(await http
          .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(data))
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> get(String path) async =>
      _handle(await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> login(String identifier, String password) async {
    final data = await post('/login', {
      'identifier': identifier,
      'password': password,
      'device_name': 'Flutter Android',
    });
    token = data['token'] as String?;
    return data;
  }

  static Future<void> logout() async {
    try {
      await post('/logout', {});
    } finally {
      token = null;
    }
  }

  static Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> body) =>
      post('/hr/employees', body);
}