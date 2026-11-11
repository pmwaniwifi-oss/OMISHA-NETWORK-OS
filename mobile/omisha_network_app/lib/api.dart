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


class AcquisitionProgress {
  const AcquisitionProgress({
    required this.id,
    required this.plan,
    required this.status,
    required this.identityStatus,
    required this.paymentRequest,
    required this.serviceOrder,
  });

  final String id;
  final String plan;
  final String status;
  final String identityStatus;
  final String? paymentRequest;
  final String? serviceOrder;

  factory AcquisitionProgress.fromJson(Map<String, dynamic> json) {
    String requiredValue(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty || value.length > 160) {
        throw const ApiException('The acquisition response was invalid.');
      }
      return value;
    }

    String? optionalValue(String key) {
      final value = json[key];
      if (value == null || value == '') return null;
      if (value is! String || value.length > 160) {
        throw const ApiException('The acquisition response was invalid.');
      }
      return value;
    }

    return AcquisitionProgress(
      id: requiredValue('name'),
      plan: requiredValue('requested_plan'),
      status: requiredValue('acquisition_status'),
      identityStatus: requiredValue('identity_status'),
      paymentRequest: optionalValue('payment_request'),
      serviceOrder: optionalValue('service_order'),
    );
  }
}

class ServiceOrderProjection {
  const ServiceOrderProjection({
    required this.id,
    required this.plan,
    required this.status,
    required this.externalServiceId,
  });

  final String id;
  final String plan;
  final String status;
  final String? externalServiceId;

  factory ServiceOrderProjection.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final plan = json['requested_plan'];
    final status = json['service_status'];
    final external = json['external_service_id'];
    if (id is! String || id.isEmpty || id.length > 160 ||
        plan is! String || plan.isEmpty || plan.length > 160 ||
        status is! String || status.isEmpty || status.length > 80 ||
        (external != null && (external is! String || external.length > 160))) {
      throw const ApiException('The service order response was invalid.');
    }
    return ServiceOrderProjection(
      id: id,
      plan: plan,
      status: status,
      externalServiceId: external as String?,
    );
  }
}

class NMSContractReference {
  const NMSContractReference({required this.number, required this.nmsId});

  final String number;
  final int nmsId;

  factory NMSContractReference.fromJson(Map<String, dynamic> json) {
    final number = json['number'];
    final id = json['nms_id'];
    if (number is! String || number.isEmpty || number.length > 64 ||
        id is! int || id <= 0) {
      throw const ApiException('The network reference response was invalid.');
    }
    return NMSContractReference(number: number, nmsId: id);
  }
}

class InstallationJob {
  const InstallationJob({required this.id, required this.acquisition, required this.outcome,
    required this.ontVendor, required this.ontModel, required this.ontSerial, required this.ontMac, required this.oltReference,
    required this.fiberConnected, required this.ontPowered, required this.opticalTestPassed,
    required this.opticalRxDbm, required this.wanLinkUp});

  final String id, acquisition, outcome, ontVendor, ontModel, ontSerial, ontMac, oltReference;
  final bool fiberConnected, ontPowered, opticalTestPassed, wanLinkUp;
  final double? opticalRxDbm;

  factory InstallationJob.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.length > 160) throw const ApiException('Installation job response was invalid.');
      return value;
    }
    bool check(String key) => json[key] == 1 || json[key] == true;
    final optical = json['optical_rx_dbm'];
    if (optical != null && optical is! num) throw const ApiException('Installation job response was invalid.');
    return InstallationJob(id: text('name'), acquisition: text('acquisition_request'),
      outcome: text('installation_outcome'), ontVendor: text('ont_vendor'), ontModel: text('ont_model'),
      ontSerial: text('ont_serial'), ontMac: text('ont_mac'),
      oltReference: text('olt_reference'), fiberConnected: check('fiber_connected'),
      ontPowered: check('ont_powered'), opticalTestPassed: check('optical_test_passed'),
      opticalRxDbm: (optical as num?)?.toDouble(), wanLinkUp: check('wan_link_up'));
  }
}

class NMSModemReference {
  const NMSModemReference({required this.installationJob, required this.modemId, required this.matchStatus});
  final String installationJob;
  final int modemId;
  final String matchStatus;

  factory NMSModemReference.fromJson(Map<String, dynamic> json) {
    final job = json['installation_job'];
    final id = json['nms_modem_id'];
    final status = json['match_status'];
    if (job is! String || job.isEmpty || job.length > 160 || id is! int || id <= 0 || status != 'exact_mac_match') {
      throw const ApiException('The NMS device match response was invalid.');
    }
    return NMSModemReference(installationJob: job, modemId: id, matchStatus: status as String);
  }
}

class InstallationCloseout {
  const InstallationCloseout({required this.outcome, required this.ontVendor, required this.ontModel,
    required this.ontSerial, required this.ontMac, required this.oltReference,
    required this.fiberConnected, required this.ontPowered, required this.opticalTestPassed,
    required this.opticalRxDbm, required this.wanLinkUp, required this.failureCode,
    required this.technicianNotes});
  final String outcome, ontVendor, ontModel, ontSerial, ontMac, oltReference, failureCode, technicianNotes;
  final bool fiberConnected, ontPowered, opticalTestPassed, wanLinkUp;
  final double? opticalRxDbm;

  Map<String, dynamic> toJson() => {
    'installation_outcome': outcome,
    'ont_vendor': ontVendor,
    'ont_model': ontModel,
    'ont_serial': ontSerial,
    'ont_mac': ontMac,
    'olt_reference': oltReference,
    'fiber_connected': fiberConnected,
    'ont_powered': ontPowered,
    'optical_test_passed': opticalTestPassed,
    'optical_rx_dbm': opticalRxDbm,
    'wan_link_up': wanLinkUp,
    'failure_code': failureCode,
    'technician_notes': technicianNotes,
  };
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


  Future<AcquisitionProgress> getAcquisitionProgress({
    required String accessToken,
    required String acquisitionId,
  }) async {
    if (acquisitionId.isEmpty || acquisitionId.length > 140) {
      throw const ApiException('The acquisition reference was invalid.');
    }
    final response = await _send(
      'GET',
      'v1/me/isp/acquisitions/${Uri.encodeComponent(acquisitionId)}',
      token: accessToken,
    );
    final value = response['acquisition'];
    if (value is! Map) {
      throw const ApiException('The acquisition response was invalid.');
    }
    return AcquisitionProgress.fromJson(Map<String, dynamic>.from(value));
  }

  Future<ServiceOrderProjection> getServiceOrder({
    required String accessToken,
    required String serviceOrderId,
  }) async {
    if (serviceOrderId.isEmpty || serviceOrderId.length > 140) {
      throw const ApiException('The service order reference was invalid.');
    }
    final response = await _send(
      'GET',
      'v1/me/isp/service-orders/${Uri.encodeComponent(serviceOrderId)}',
      token: accessToken,
    );
    final value = response['service_order'];
    if (value is! Map) {
      throw const ApiException('The service order response was invalid.');
    }
    return ServiceOrderProjection.fromJson(Map<String, dynamic>.from(value));
  }

  Future<NMSContractReference> getNMSContractReference({
    required String accessToken,
    required String number,
  }) async {
    if (number.isEmpty || number.length > 64) {
      throw const ApiException('The network contract reference was invalid.');
    }
    final response = await _send(
      'GET',
      'v1/me/isp/nms/contracts/${Uri.encodeComponent(number)}',
      token: accessToken,
    );
    final value = response['contract_reference'];
    if (value is! Map) {
      throw const ApiException('The network reference response was invalid.');
    }
    return NMSContractReference.fromJson(Map<String, dynamic>.from(value));
  }

  Future<List<InstallationJob>> getMyInstallationJobs({required String accessToken}) async {
    final response = await _send('GET', 'v1/me/isp/technician/installation-jobs', token: accessToken);
    final values = response['installation_jobs'];
    if (values is! List || values.length > 50 || values.any((value) => value is! Map)) {
      throw const ApiException('The installation job list response was invalid.');
    }
    return values.map((value) => InstallationJob.fromJson(Map<String, dynamic>.from(value as Map))).toList(growable: false);
  }

  Future<NMSModemReference> getNMSReferenceForInstallationJob({required String accessToken, required String jobId}) async {
    if (jobId.isEmpty || jobId.length > 140) throw const ApiException('The installation job reference was invalid.');
    final response = await _send('GET', 'v1/me/isp/technician/installation-jobs/${Uri.encodeComponent(jobId)}/nms-reference', token: accessToken);
    final value = response['nms_modem_reference'];
    if (value is! Map) throw const ApiException('The NMS device match response was invalid.');
    return NMSModemReference.fromJson(Map<String, dynamic>.from(value));
  }

  Future<String> submitInstallationCloseout({required String accessToken, required String jobId, required InstallationCloseout closeout}) async {
    if (jobId.isEmpty || jobId.length > 140) throw const ApiException('The installation job reference was invalid.');
    final response = await _send('POST', 'v1/me/isp/technician/installation-jobs/${Uri.encodeComponent(jobId)}/closeout',
      token: accessToken, body: closeout.toJson());
    final value = response['installation_closeout'];
    if (value is! Map || value['installation_job'] != jobId ||
        (value['state'] != 'submitted' && value['state'] != 'already_submitted')) {
      throw const ApiException('The installation closeout response was invalid.');
    }
    return value['state'] as String;
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
