import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';

/// Shared HTTP client with proper headers and error handling
class ApiClient {
  final http.Client _client = http.Client();

  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  Map<String, String> get _headers => {
    'User-Agent': ApiConstants.userAgent,
    'Accept': 'application/json',
    'Accept-Language': 'de-DE,de;q=0.9',
  };

  /// GET that expects a Map response
  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? queryParams,
  }) async {
    final response = await _rawGet(url, queryParams: queryParams);
    final decoded = json.decode(response.body);

    // HAFAS sometimes returns the data differently
    if (decoded is Map<String, dynamic>) return decoded;

    // If it's a list, wrap it
    if (decoded is List) return {'items': decoded};

    throw ApiException(response.statusCode, 'Unexpected response format');
  }

  /// GET that returns raw decoded JSON (List or Map)
  Future<dynamic> getList(
    String url, {
    Map<String, String>? queryParams,
  }) async {
    final response = await _rawGet(url, queryParams: queryParams);
    return json.decode(response.body);
  }

  Future<http.Response> _rawGet(
    String url, {
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return response;
  }

  Future<Map<String, dynamic>> post(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(url);
    final response = await _client.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(response.statusCode, response.body);
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode)';
}
