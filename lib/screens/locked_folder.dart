// Locked folder (web: /locked): PIN setup or unlock, then the locked timeline.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/asset_actions.dart';
import '../widgets/timeline_view.dart';

class LockedFolderScreen extends StatefulWidget {
  final ImmichApi api;
  const LockedFolderScreen({super.key, required this.api});

  @override
  State<LockedFolderScreen> createState() => _LockedFolderScreenState();
}

enum _State { loading, setup, locked, open }

class _LockedFolderScreenState extends State<LockedFolderScreen> {
  _State _state = _State.loading;
  TimelineSource? _source;
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _source?.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final s = await widget.api.authStatus();
      if (!mounted) return;
      final until = DateTime.tryParse(s['pinExpiresAt'] ?? '');
      if (s['pinCode'] != true) {
        setState(() => _state = _State.setup);
      } else if (until != null && until.isAfter(DateTime.now())) {
        await _open();
      } else {
        setState(() => _state = _State.locked);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _State.locked;
        _error = '$e';
      });
    }
  }

  Future<void> _open() async {
    final src = await TimelineSource.create(widget.api, TimelineQuery.locked);
    if (!mounted) return src.dispose();
    setState(() {
      _source = src;
      _state = _State.open;
    });
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return;
    if (_state == _State.setup && pin != _pin2.text.trim()) {
      setState(() => _error = t('password_does_not_match'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_state == _State.setup) {
        await widget.api.setupPinCode(pin);
        // The PIN now exists; a retry after a failed unlock must not set it up again.
        if (mounted) setState(() => _state = _State.locked);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t('pin_code_setup_successfully'))));
        }
      }
      await widget.api.unlockSession(pin);
      _pin.clear();
      _pin2.clear();
      await _open();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException && e.status == 400 ? t('wrong_pin_code') : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lock() async {
    try {
      await widget.api.lockSession();
    } catch (_) {}
    if (!mounted) return; // dispose() already freed _source
    _source?.dispose();
    setState(() {
      _source = null;
      _state = _State.locked;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _State.loading:
        return const Center(child: CircularProgressIndicator());
      case _State.open:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _lock,
                icon: const Icon(Icons.lock_outline),
                label: Text(t('lock')),
              ),
            ),
          ),
          Expanded(
            child: TimelineView(
              api: widget.api,
              source: _source!,
              mode: TimelineMode.locked,
              emptyText: t('no_assets_to_show'),
            ),
          ),
        ]);
      case _State.setup:
      case _State.locked:
        final setup = _state == _State.setup;
        final theme = Theme.of(context);
        InputDecoration deco(String label) => InputDecoration(
              labelText: label,
              helperText: t('linux_pin_digits'),
              counterText: '',
              border: const OutlineInputBorder(),
            );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(setup ? t('new_pin_code') : t('enter_your_pin_code'),
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(setup ? t('new_pin_code_subtitle') : t('enter_your_pin_code_subtitle'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: _pin,
                autofocus: true,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco(setup ? t('new_pin_code') : t('user_pin_code_settings')),
                onSubmitted: (_) => setup ? null : _submit(),
              ),
              if (setup) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pin2,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: deco(t('confirm_new_pin_code')),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(setup ? t('create') : t('linux_unlock')),
                ),
              ),
            ]),
          ),
        );
    }
  }
}
