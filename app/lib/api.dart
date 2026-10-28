import 'dart:convert';

import 'package:http/http.dart' as http;

class EsmaApi {
  EsmaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl = const String.fromEnvironment('ESMA_API_URL');

  Uri _uri(String path) => Uri.parse(baseUrl.isEmpty ? Uri.base.resolve(path).toString() : '$baseUrl$path');

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _client.get(_uri(path), headers: {'Accept': 'application/json'});
    return _decode(response);
  }

  Future<Map<String, dynamic>> send(String method, String path, [Map<String, dynamic>? body]) async {
    final request = http.Request(method, _uri(path));
    request.headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request);
    return _decode(await http.Response.fromStream(streamed));
  }

  Map<String, dynamic> _decode(http.Response response) {
    final data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(data['error']?.toString() ?? 'Serverfehler (${response.statusCode})');
    }
    return data;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
