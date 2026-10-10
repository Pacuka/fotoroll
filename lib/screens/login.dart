import 'package:flutter/material.dart';

import '../widgets/brand.dart';
import '../api.dart';
import '../i18n.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function(Credentials) onLoggedIn;
  final String? initialServer;

  const LoginScreen({super.key, required this.onLoggedIn, this.initialServer});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _server = TextEditingController(text: widget.initialServer ?? '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  bool _useApiKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_server.text.trim().isEmpty) {
      setState(() => _error = t('login_form_server_empty'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Credentials creds;
      if (_useApiKey) {
        creds = Credentials(
          serverUrl: ImmichApi.normalizeServerUrl(_server.text),
          apiKey: _apiKey.text.trim(),
        );
      } else {
        creds = await ImmichApi.login(_server.text, _email.text, _password.text);
      }
      await ImmichApi(creds).me(); // validates the credentials
      await widget.onLoggedIn(creds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: FotorollLogo(size: 96, vertical: true)),
                  const SizedBox(height: 8),
                  Text(t('linux_login_subtitle'), textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _server,
                    decoration: InputDecoration(
                      labelText: t('login_form_endpoint_url'),
                      hintText: t('login_form_endpoint_hint'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(t('linux_login_method_password'))),
                      ButtonSegment(value: true, label: Text(t('api_key'))),
                    ],
                    selected: {_useApiKey},
                    onSelectionChanged: (s) => setState(() => _useApiKey = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_useApiKey)
                    TextField(
                      controller: _apiKey,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t('api_key'),
                        helperText: t('linux_api_key_help'),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    )
                  else ...[
                    TextField(
                      controller: _email,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: t('email'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: t('password'),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(t('login')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
