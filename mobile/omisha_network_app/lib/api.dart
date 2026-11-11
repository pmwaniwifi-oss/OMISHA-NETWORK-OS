import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class WorkspaceContext {
  const WorkspaceContext({
    required this.id,
    required this.organization,
    required this.workspace,
    required this.capabilities,
    required this.roleLabels,
  });

  final String id;
  final String organization;
  final String workspace;
  final List<String> capabilities;
  final List<String> roleLabels;

  factory WorkspaceContext.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty || value.length > 160) {
        throw const ApiException('The account response was invalid.');
      }
      return value;
    }

    List<String> strings(String key) {
      final value = json[key];
      if (value is! List ||
          value.length > 100 ||
          value.any((item) => item is! String || item.length > 100)) {
        throw const ApiException('The account response was invalid.');
      }
      return value.cast<String>();
    }

    return WorkspaceContext(
      id: requiredString('context_id'),
      organization: requiredString('organization_name'),
      workspace: requiredString('workspace_type'),
      capabilities: strings('capabilities'),
      roleLabels: strings('role_labels'),
    );
  }

  factory WorkspaceContext.fromSessionJson(Map<String, dynamic> json) {
    return WorkspaceContext.fromJson(json);
  }
}

class ApiSession {
  const ApiSession({required this.accessToken, required this.context});

  final String accessToken;
  final WorkspaceContext context;

  factory ApiSession.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    final context = json['active_context'];
    if (token is! String || token.length < 24 || token.length > 8192 || context is! Map) {
      throw const ApiException('The sign-in response was invalid.');
    }
    return ApiSession(
      accessToken: token,
      context: WorkspaceContext.fromSessionJson(Map<String, dynamic>.from(context)),
    );
  }
}

class OmishaApi {
  OmishaApi(String baseUrl) : _baseUri = _validatedBaseUri(baseUrl);

  final Uri _baseUri;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 20);

  static Uri _validatedBaseUri(String value) {
    final uri = Uri.tryParse(value);
    final localHost = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(localHost && uri.scheme == 'http'))) {
      throw const ApiException(
        'Set OMISHA_API_BASE_URL to an HTTPS API endpoint. HTTP is allowed only for localhost development.',
      );
    }
    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: normalizedPath);
  }

  Future<String> startChallenge(String identifier) async {
    final response = await _send(
      'POST',
      'v1/auth/challenges',
      body: {'identifier': identifier.trim()},
    );
    final challengeId = response['challenge_id'];
    if (challengeId is! String || challengeId.isEmpty || challengeId.length > 200) {
      throw const ApiException('The sign-in service returned an invalid response.');
    }
    return challengeId;
  }

  Future<String> verifyChallenge({
    required String challengeId,
    required String code,
  }) async {
    final response = await _send(
      'POST',
      'v1/auth/challenges/verify',
      body: {'challenge_id': challengeId, 'code': code.trim()},
    );
    final identityToken = response['identity_token'];
    if (identityToken is! String ||
        identityToken.length < 24 ||
        identityToken.length > 8192) {
      throw const ApiException('The verification response was invalid.');
    }
    return identityToken;
  }

  Future<List<WorkspaceContext>> listContexts(String identityToken) async {
    final response = await _send('GET', 'v1/me/contexts', token: identityToken);
    final values = response['contexts'];
    if (values is! List || values.length > 50) {
      throw const ApiException('The account list response was invalid.');
    }
    return values
        .map((value) {
          if (value is! Map) {
            throw const ApiException('The account list response was invalid.');
          }
          return WorkspaceContext.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);
  }

  Future<ApiSession> activateContext({
    required String identityToken,
    required WorkspaceContext context,
  }) async {
    final response = await _send(
      'POST',
      'v1/me/contexts/activate',
      token: identityToken,
      body: {'context_id': context.id},
    );
    return ApiSession.fromJson(response);
  }

  Future<ApiSession> resumeSession(String accessToken) async {
    final response = await _send('GET', 'v1/me', token: accessToken);
    return ApiSession(
      accessToken: accessToken,
      context: WorkspaceContext.fromSessionJson(
        Map<String, dynamic>.from(response['active_context'] as Map),
      ),
    );
  }

  Future<void> logout(String accessToken) async {
    await _send('POST', 'v1/auth/logout', token: accessToken, body: const {});
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(method, _baseUri.resolve(path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }

    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const ApiException('Your session expired. Please sign in again.', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'The service could not complete this request. Please try again later.',
        statusCode: response.statusCode,
      );
    }

    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const ApiException('The server response exceeded the allowed size.');
      }
      bytes.addAll(chunk);
    }

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('The server response was invalid.');
      }
      return decoded;
    } on FormatException {
      throw const ApiException('The server response was invalid.');
    }
  }

  void close() => _client.close(force: true);
}
