import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/school_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/users_repository.dart';

const _lastLoginKey = 'last_login';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreLastLogin();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreLastLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastLoginKey);
      if (mounted && last != null && _username.text.isEmpty) {
        _username.text = last;
        _passwordFocus.requestFocus();
      }
    } catch (_) {
      // Remembering the login name is only a convenience.
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Saisissez votre identifiant et votre mot de passe.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(_username.text, _password.text);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _lastLoginKey,
          _username.text.trim().toLowerCase(),
        );
      } catch (_) {}
    } on AuthException catch (e) {
      // A short pause makes guessing passwords by trial and error slow.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        setState(() {
          _error = e.message;
          _password.clear();
        });
        _passwordFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connexion impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDefaultHint = ref.watch(defaultAdminHintProvider).value ?? false;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connexion', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            'Identifiez-vous pour accéder à la gestion de scolarité.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _username,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'Identifiant',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            focusNode: _passwordFocus,
            obscureText: !_show,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _show ? 'Masquer' : 'Afficher',
                icon: Icon(
                  _show
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Se connecter'),
          ),
          if (showDefaultHint) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0D690)),
              ),
              child: const Text(
                'Première utilisation : identifiant « admin », mot de passe « admin ». '
                'Il vous sera demandé de le changer aussitôt.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          final formArea = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!wide) ...[
                    const SchoolLogo(size: 88),
                    const SizedBox(height: 16),
                  ],
                  form,
                ],
              ),
            ),
          );
          if (!wide) return formArea;
          return Row(
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navy, AppColors.navyDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 240,
                            height: 240,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.gold,
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 30,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: const ClipOval(child: SchoolLogo(size: 220)),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Complexe Scolaire Bilingue\nMariane et Paul',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gestion de scolarité',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(flex: 4, child: formArea),
            ],
          );
        },
      ),
    );
  }
}
