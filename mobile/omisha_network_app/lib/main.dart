import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import 'api.dart';

const _apiBaseUrl = String.fromEnvironment('OMISHA_API_BASE_URL');
const _googleServerClientId = String.fromEnvironment('OMISHA_GOOGLE_SERVER_CLIENT_ID');
const _googleIdentityChannel = MethodChannel('com.omisha.network_os/google_identity');
const _sessionKey = 'omisha.scoped_access_token';
const _identitySessionKey = 'omisha.identity_session_token';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OmishaApp());
}

class OmishaApp extends StatefulWidget {
  const OmishaApp({super.key});

  @override
  State<OmishaApp> createState() => _OmishaAppState();
}

class _OmishaAppState extends State<OmishaApp> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final OmishaApi? _api;
  String? _configurationError;
  String? _identityToken;
  String? _error;
  bool _enrollmentPending = false;
  List<WorkspaceContext> _contexts = const [];
  ApiSession? _session;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    try {
      _api = OmishaApi(_apiBaseUrl);
    } on ApiException catch (exception) {
      _api = null;
      _configurationError = exception.message;
    }
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (_api == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final token = await _secureStorage.read(key: _sessionKey);
      final identityToken = await _secureStorage.read(key: _identitySessionKey);
      if (token != null && token.isNotEmpty && identityToken != null && identityToken.isNotEmpty) {
        final restored = await _api.resumeSession(
          accessToken: token,
          identityToken: identityToken,
        );
        if (!mounted) return;
        setState(() {
          _session = restored;
          _busy = false;
        });
        return;
      }
      if (token != null || identityToken != null) {
        await _secureStorage.delete(key: _sessionKey);
        await _secureStorage.delete(key: _identitySessionKey);
      }
    } on ApiException catch (exception) {
      if (exception.statusCode == 401) {
        await _secureStorage.delete(key: _sessionKey);
        await _secureStorage.delete(key: _identitySessionKey);
      }
      _error = exception.message;
    } catch (_) {
      _error = 'Could not restore the saved sign-in session.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _signInWithGoogle() async {
    final api = _api;
    if (api == null) return;
    if (_googleServerClientId.isEmpty) {
      setState(() {
        _error = 'Google sign-in is not configured for this build yet.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await api.startGoogleChallenge();
      final googleIdToken = await _googleIdentityChannel.invokeMethod<String>(
        'googleIdToken',
        {
          'serverClientId': _googleServerClientId,
          'nonce': challenge.nonce,
        },
      );
      if (googleIdToken == null || googleIdToken.isEmpty) {
        throw const ApiException('Google did not return a sign-in token.');
      }
      final identityToken = await api.exchangeGoogleIdToken(
        googleIdToken: googleIdToken,
        challengeId: challenge.id,
        nonce: challenge.nonce,
      );
      await _finishIdentityAuthentication(identityToken);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeMessage(exception);
      });
    }
  }

  Future<void> _redeemInvitationToken(String invitationToken) async {
    final api = _api;
    final identityToken = _identityToken;
    if (api == null || identityToken == null) return;
    final token = invitationToken.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await api.redeemInvitation(
        identityToken: identityToken,
        invitationToken: token,
      );
      if (result['status'] == 'pending_onboarding') {
        if (!mounted) return;
        setState(() {
          _enrollmentPending = true;
          _busy = false;
        });
        return;
      }
      if (result['status'] != 'active') {
        throw const ApiException('The invitation could not be accepted.');
      }
      final contexts = await api.listContexts(identityToken);
      if (contexts.isEmpty) {
        throw const ApiException('Invitation accepted, but no active workspace is available.');
      }
      if (!mounted) return;
      setState(() {
        _contexts = contexts;
        _enrollmentPending = false;
        _busy = false;
      });
      if (contexts.length == 1) {
        await _activateContext(contexts.single);
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeMessage(exception);
      });
    }
  }

  Future<String?> _chooseInvitationRole(List<String> roles) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create invitation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in roles)
              ListTile(
                title: Text(role),
                onTap: () => Navigator.of(dialogContext).pop(role),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _createInvitation() async {
    final api = _api;
    final session = _session;
    if (api == null || session == null) return;
    final roles = session.context.roleLabels;
    late final InvitationResult invitation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (session.context.workspace == 'omisha_workspace' &&
          roles.contains('omisha.platform_admin')) {
        final action = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('OMISHA invitations'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Add ISP organization'),
                  subtitle: const Text('Create tenant and invite its first owner'),
                  onTap: () => Navigator.of(dialogContext).pop('isp'),
                ),
                ListTile(
                  title: const Text('Invite OMISHA staff'),
                  onTap: () => Navigator.of(dialogContext).pop('staff'),
                ),
              ],
            ),
          ),
        );
        if (action == null) return;
        if (action == 'isp') {
          final controller = TextEditingController();
          final label = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Add ISP organization'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'ISP / organization name'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                  child: const Text('Create ISP invite'),
                ),
              ],
            ),
          );
          controller.dispose();
          if (label == null || label.isEmpty) return;
          invitation = await api.createISP(
            accessToken: session.accessToken,
            displayLabel: label,
          );
        } else {
          invitation = await api.createWorkspaceInvitation(
            accessToken: session.accessToken,
            roleCode: 'omisha.staff',
          );
        }
      } else {
        final rolesToInvite = <String>[
          if (roles.contains('isp.owner')) 'isp.admin',
          'isp.technician',
          'isp.sales',
          'isp.support',
          'isp.finance',
          'isp.customer',
        ];
        final role = await _chooseInvitationRole(rolesToInvite);
        if (role == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        invitation = await api.createWorkspaceInvitation(
          accessToken: session.accessToken,
          roleCode: role,
        );
      }
      final shareText = 'OMISHA NETWORK OS invitation\\n'
          'Organization: ${invitation.organization}\\n'
          'Role: ${invitation.roleCode}\\n'
          'Expires: ${invitation.expiresAt}\\n\\n'
          'Invitation token (keep private):\\n${invitation.token}\\n\\n'
          'Open OMISHA NETWORK OS, sign in with Google, and enter this invitation token.';
      await _googleIdentityChannel.invokeMethod<void>(
        'shareInvitation',
        {'text': shareText},
      );
    } catch (exception) {
      if (mounted) setState(() => _error = _safeMessage(exception));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishIdentityAuthentication(String identityToken) async {
    final api = _api;
    if (api == null) {
      if (mounted) setState(() {
        _busy = false;
        _error = 'The sign-in service is not configured.';
      });
      return;
    }
    try {
      final contexts = await api.listContexts(identityToken);
      if (!mounted) return;
      setState(() {
        _identityToken = identityToken;
        _contexts = contexts;
        _enrollmentPending = false;
        _busy = false;
      });
      if (contexts.isEmpty) return;
      if (contexts.length == 1) {
        await _activateContext(contexts.single);
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeMessage(exception);
      });
    }
  }

  Future<void> _activateContext(WorkspaceContext context) async {
    final identityToken = _identityToken;
    if (_api == null || identityToken == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await _api.activateContext(
        identityToken: identityToken,
        context: context,
      );
      await _secureStorage.write(key: _sessionKey, value: session.accessToken);
      await _secureStorage.write(key: _identitySessionKey, value: session.identityToken);
      if (!mounted) return;
      setState(() {
        _session = session;
        _identityToken = null;
        _contexts = const [];
        _busy = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeMessage(exception);
      });
    }
  }

  Future<void> _openContextPicker() async {
    final session = _session;
    if (_api == null || session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final contexts = await _api.listContexts(session.identityToken);
      if (!mounted) return;
      if (contexts.isEmpty) {
        throw const ApiException('No active account access is assigned to this sign-in.');
      }
      setState(() {
        _identityToken = session.identityToken;
        _contexts = contexts;
        _busy = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeMessage(exception);
      });
    }
  }

  Future<void> _logout() async {
    final session = _session;
    final api = _api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identityToken = session?.identityToken ?? _identityToken;
      if (identityToken != null && api != null) {
        await api.logout(identityToken);
      }
      try {
        await _googleIdentityChannel.invokeMethod<void>('clearCredentialState');
      } catch (_) {
        // The OMISHA server session is still cleared locally even if provider cleanup fails.
      }
    } catch (_) {
      // Always clear local credentials; revocation is retried/handled server-side.
    } finally {
      await _secureStorage.delete(key: _sessionKey);
      await _secureStorage.delete(key: _identitySessionKey);
      if (!mounted) return;
      setState(() {
        _session = null;
        _identityToken = null;
        _enrollmentPending = false;
        _contexts = const [];
          _busy = false;
      });
    }
  }

  void _cancelContextPicker() {
    setState(() {
      _identityToken = null;
      _enrollmentPending = false;
      _contexts = const [];
      _error = null;
    });
  }

  String _safeMessage(Object exception) {
    if (exception is ApiException) return exception.message;
    return 'The request could not be completed. Please try again.';
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMISHA NETWORK OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF075B55),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F8F7),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
      ),
      home: _buildHome(),
    );
  }

  bool get _canCreateInvitation {
    final roles = _session?.context.roleLabels ?? const <String>[];
    return roles.contains('omisha.platform_admin') ||
        roles.contains('isp.owner') ||
        roles.contains('isp.admin');
  }

  Widget _buildHome() {
    if (_busy) return const _LoadingPage();
    if (_configurationError != null) {
      return _MessagePage(
        title: 'OMISHA NETWORK OS',
        message: _configurationError!,
        detail: 'Configure OMISHA_API_BASE_URL at build time. Do not use a public or production HTTP endpoint.',
      );
    }
    final session = _session;
    if (_identityToken != null && _contexts.isEmpty) {
      return _InvitationAcceptPage(
        pending: _enrollmentPending,
        error: _error,
        onRedeem: _redeemInvitationToken,
        onLogout: _logout,
      );
    }
    if (_contexts.isNotEmpty && _identityToken != null) {
      return _ContextPickerPage(
        contexts: _contexts,
        error: _error,
        onSelect: _activateContext,
        onCancel: _cancelContextPicker,
        canReturnToWorkspace: _session != null,
      );
    }
    if (session != null) {
      return _WorkspacePage(
        contextInfo: session.context,
        error: _error,
        onSwitch: _openContextPicker,
        onLogout: _logout,
        onCreateInvitation: _canCreateInvitation ? _createInvitation : null,
      );
    }
    return _SignInPage(
      googleEnabled: _googleServerClientId.isNotEmpty,
      busy: _busy,
      error: _error,
      onGoogleSignIn: _signInWithGoogle,
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('OMISHA NETWORK OS'),
            ],
          ),
        ),
      );
}

class _SignInPage extends StatelessWidget {
  const _SignInPage({
    required this.googleEnabled,
    required this.busy,
    required this.error,
    required this.onGoogleSignIn,
  });

  final bool googleEnabled;
  final bool busy;
  final String? error;
  final Future<void> Function() onGoogleSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.hub_outlined, color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 24),
                      Text('OMISHA NETWORK OS', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Text('Sign in with Google', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('Customers, ISP users and OMISHA staff all use Google sign-in. Your approved workspaces and access are assigned by OMISHA and your ISP administrator.'),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy || !googleEnabled ? null : onGoogleSignIn,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(googleEnabled
                              ? 'Continue with Google'
                              : 'Google sign-in setup required'),
                        ),
                      ),
                      if (busy) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        _InlineError(error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationAcceptPage extends StatefulWidget {
  const _InvitationAcceptPage({
    required this.pending,
    required this.error,
    required this.onRedeem,
    required this.onLogout,
  });

  final bool pending;
  final String? error;
  final Future<void> Function(String token) onRedeem;
  final VoidCallback onLogout;

  @override
  State<_InvitationAcceptPage> createState() => _InvitationAcceptPageState();
}

class _InvitationAcceptPageState extends State<_InvitationAcceptPage> {
  final _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tokenController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OMISHA NETWORK OS'),
        actions: [
          IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pending ? 'Onboarding is pending' : 'Accept your invitation',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(widget.pending
                          ? 'Your customer invitation is recorded. ISP verification, serviceability and payment checks must finish before service access is activated.'
                          : 'Sign-in is verified. Paste the private invitation token sent by your ISP or OMISHA administrator.'),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _tokenController,
                        maxLength: 128,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Invitation token',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (widget.error != null) ...[
                        const SizedBox(height: 12),
                        _InlineError(widget.error!),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _tokenController.text.trim().length < 40
                              ? null
                              : () => widget.onRedeem(_tokenController.text),
                          child: const Text('Accept invitation'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextPickerPage extends StatelessWidget {
  const _ContextPickerPage({
    required this.contexts,
    required this.error,
    required this.onSelect,
    required this.onCancel,
    required this.canReturnToWorkspace,
  });

  final List<WorkspaceContext> contexts;
  final String? error;
  final Future<void> Function(WorkspaceContext context) onSelect;
  final VoidCallback onCancel;
  final bool canReturnToWorkspace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your workspace'), leading: IconButton(onPressed: onCancel, icon: const Icon(Icons.arrow_back))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('These workspaces were returned for your verified sign-in. Selecting one does not add permissions.'),
          const SizedBox(height: 16),
          if (error != null) _InlineError(error!),
          for (final workspace in contexts)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(child: Icon(Icons.business_outlined)),
                title: Text(workspace.organization, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${workspace.workspace} · ${workspace.roleLabels.join(', ')}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelect(workspace),
              ),
            ),
          TextButton(
            onPressed: onCancel,
            child: Text(canReturnToWorkspace ? 'Return to current workspace' : 'Cancel sign-in'),
          ),
        ],
      ),
    );
  }
}

class _WorkspacePage extends StatelessWidget {
  const _WorkspacePage({
    required this.contextInfo,
    required this.error,
    required this.onSwitch,
    required this.onLogout,
    required this.onCreateInvitation,
  });

  final WorkspaceContext contextInfo;
  final String? error;
  final VoidCallback onSwitch;
  final VoidCallback onLogout;
  final VoidCallback? onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = contextInfo.capabilities.toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('OMISHA NETWORK OS'),
        actions: [
          IconButton(tooltip: 'Switch workspace', onPressed: onSwitch, icon: const Icon(Icons.swap_horiz)),
          IconButton(tooltip: 'Sign out', onPressed: onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contextInfo.organization, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${contextInfo.workspace} workspace'),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: contextInfo.roleLabels.map((role) => Chip(label: Text(role))).toList(),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _InlineError(error!),
          ],
          const SizedBox(height: 20),
          Text('Your access', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (capabilities.isEmpty)
            const Card(child: ListTile(title: Text('No active modules are assigned to this workspace.')))
          else
            for (final capability in capabilities)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(_friendlyCapability(capability)),
                  subtitle: Text(capability),
                ),
              ),
          if (onCreateInvitation != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreateInvitation,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Create invitation'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Screens and actions are only a user interface. The OMISHA API must enforce every permission and tenant boundary on every request.'),
        ],
      ),
    );
  }

  String _friendlyCapability(String capability) {
    return capability
        .split(RegExp(r'[._-]'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({
    required this.title,
    required this.message,
    required this.detail,
  });

  final String title;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.settings_ethernet, size: 38),
                      const SizedBox(height: 16),
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(message),
                      const SizedBox(height: 8),
                      Text(detail, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}
