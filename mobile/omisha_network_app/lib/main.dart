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
      if (contexts.isEmpty) {
        throw const ApiException('No active account access is assigned to this sign-in.');
      }
      if (!mounted) return;
      setState(() {
        _identityToken = identityToken;
        _contexts = contexts;
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
      if (session != null && api != null) {
        await api.logout(session.identityToken);
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
        _contexts = const [];
          _busy = false;
      });
    }
  }

  void _cancelContextPicker() {
    setState(() {
      _identityToken = null;
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
  });

  final WorkspaceContext contextInfo;
  final String? error;
  final VoidCallback onSwitch;
  final VoidCallback onLogout;

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
