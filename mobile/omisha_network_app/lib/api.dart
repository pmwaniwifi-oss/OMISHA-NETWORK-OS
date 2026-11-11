import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

class WorkspaceInvitation {
  const WorkspaceInvitation({
    required this.id,
    required this.roleCode,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String roleCode;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) {
    final id = json['invitation_id'];
    final role = json['role_code'];
    final status = json['status'];
    final created = json['created_at'];
    final expires = json['expires_at'];
    if (id is! String || role is! String || status is! String ||
        created is! String || expires is! String) {
      throw const ApiException('The invitation list response was invalid.');
    }
    final createdAt = DateTime.tryParse(created);
    final expiresAt = DateTime.tryParse(expires);
    if (createdAt == null || expiresAt == null) {
      throw const ApiException('The invitation list response was invalid.');
    }
    return WorkspaceInvitation(
      id: id,
      roleCode: role,
      status: status,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

class InvitationResult {
  const InvitationResult({
    required this.id,
    required this.organization,
    required this.roleCode,
    required this.token,
    required this.expiresAt,
  });

  final String id;
  final String organization;
  final String roleCode;
  final String token;
  final String expiresAt;

  factory InvitationResult.fromJson(Map<String, dynamic> json) {
    final id = json['invitation_id'];
    final organization = json['organization_name'];
    final roleCode = json['role_code'];
    final token = json['invitation_token'];
    final expiresAt = json['expires_at'];
    if (id is! String || organization is! String || roleCode is! String ||
        token is! String || token.length < 40 || token.length > 128 ||
        expiresAt is! String) {
      throw const ApiException('The invitation response was invalid.');
    }
    return InvitationResult(
      id: id,
      organization: organization,
      roleCode: roleCode,
      token: token,
      expiresAt: expiresAt,
    );
  }
}

String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class GoogleAuthChallenge {
  const GoogleAuthChallenge({required this.id, required this.nonce});

  final String id;
  final String nonce;
}

class ApiSession {
  const ApiSession({
    required this.accessToken,
    required this.identityToken,
    required this.context,
  });

  final String accessToken;
  final String identityToken;
  final WorkspaceContext context;

  factory ApiSession.fromJson(
    Map<String, dynamic> json, {
    required String identityToken,
  }) {
    final token = json['access_token'];
    final context = json['active_context'];
    if (token is! String || token.length < 24 || token.length > 8192 || context is! Map) {
      throw const ApiException('The sign-in response was invalid.');
    }
    return ApiSession(
      accessToken: token,
      identityToken: identityToken,
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

  Future<GoogleAuthChallenge> startGoogleChallenge() async {
    final response = await _send('POST', 'v1/auth/social/google/challenge', body: const {});
    final id = response['challenge_id'];
    final nonce = response['nonce'];
    if (id is! String || id.isEmpty || id.length > 200 ||
        nonce is! String || nonce.length < 32 || nonce.length > 256) {
      throw const ApiException('The sign-in service returned an invalid challenge.');
    }
    return GoogleAuthChallenge(id: id, nonce: nonce);
  }

  Future<String> exchangeGoogleIdToken({
    required String googleIdToken,
    required String challengeId,
    required String nonce,
  }) async {
    if (googleIdToken.length < 24 || googleIdToken.length > 8192 ||
        challengeId.isEmpty || challengeId.length > 200) {
      throw const ApiException('The Google sign-in response was invalid.');
    }
    final response = await _send(
      'POST',
      'v1/auth/social/google',
      body: {'challenge_id': challengeId, 'nonce': nonce, 'id_token': googleIdToken},
    );
    final identityToken = response['identity_token'];
    if (identityToken is! String ||
        identityToken.length < 24 ||
        identityToken.length > 8192) {
      throw const ApiException('The sign-in service response was invalid.');
    }
    return identityToken;
  }

  Future<InvitationResult> createISP({
    required String accessToken,
    required String displayLabel,
  }) async {
    final response = await _send(
      'POST',
      'v1/omisha/isps',
      token: accessToken,
      body: {'display_label': displayLabel},
      extraHeaders: {'Idempotency-Key': newIdempotencyKey()},
    );
    return InvitationResult.fromJson(response);
  }

  Future<InvitationResult> createWorkspaceInvitation({
    required String accessToken,
    required String roleCode,
    int expiresInHours = 72,
  }) async {
    final response = await _send(
      'POST',
      'v1/me/invitations',
      token: accessToken,
      body: {'role_code': roleCode, 'expires_in_hours': expiresInHours},
      extraHeaders: {'Idempotency-Key': newIdempotencyKey()},
    );
    return InvitationResult.fromJson(response);
  }

  Future<List<WorkspaceInvitation>> listWorkspaceInvitations(String accessToken) async {
    final response = await _send('GET', 'v1/me/invitations', token: accessToken);
    final values = response['invitations'];
    if (values is! List || values.length > 50) {
      throw const ApiException('The invitation list response was invalid.');
    }
    return values.map((value) {
      if (value is! Map) {
        throw const ApiException('The invitation list response was invalid.');
      }
      return WorkspaceInvitation.fromJson(Map<String, dynamic>.from(value));
    }).toList(growable: false);
  }

  Future<void> revokeWorkspaceInvitation({
    required String accessToken,
    required String invitationId,
  }) async {
    if (invitationId.length > 64) {
      throw const ApiException('The invitation identifier was invalid.');
    }
    await _send(
      'DELETE',
      'v1/me/invitations/${Uri.encodeComponent(invitationId)}',
      token: accessToken,
    );
  }

  Future<Map<String, dynamic>> redeemInvitation({
    required String identityToken,
    required String invitationToken,
  }) {
    return _send(
      'POST',
      'v1/auth/invitations/redeem',
      token: identityToken,
      body: {'invitation_token': invitationToken},
    );
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
    return ApiSession.fromJson(response, identityToken: identityToken);
  }

  Future<ApiSession> resumeSession({
    required String accessToken,
    required String identityToken,
  }) async {
    final response = await _send('GET', 'v1/me', token: accessToken);
    return ApiSession(
      accessToken: accessToken,
      identityToken: identityToken,
      context: WorkspaceContext.fromSessionJson(
        Map<String, dynamic>.from(response['active_context'] as Map),
      ),
    );
  }

  Future<void> logout(String identityToken) async {
    await _send('POST', 'v1/auth/logout', token: identityToken, body: const {});
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final request = await _client.openUrl(method, _baseUri.resolve(path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    extraHeaders?.forEach((name, value) {
      request.headers.set(name, value);
    });
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
