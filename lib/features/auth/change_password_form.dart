import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/school_logo.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/users_repository.dart';

/// Current password + new password (twice). Used in the dialog opened from
/// the menu and in the screen shown after a first login or a reset.
class ChangePasswordForm extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  final Widget? extraAction;

  /// When given, a "your name" field is shown (asked at the first login) and
  /// saved together with the new password.
  final String? initialName;
  const ChangePasswordForm({
    super.key,
    required this.onDone,
    this.extraAction,
    this.initialName,
  });

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_new.text != _confirm.text) {
      setState(
        () => _error = 'Les deux nouveaux mots de passe sont différents.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      if (widget.initialName != null &&
          _name.text.trim() != widget.initialName) {
        await auth.updateOwnName(_name.text);
      }
      await auth.changePassword(_current.text, _new.text);
      if (mounted) widget.onDone();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    suffixIcon: IconButton(
      tooltip: _show ? 'Masquer' : 'Afficher',
      icon: Icon(
        _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: () => setState(() => _show = !_show),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.initialName != null) ...[
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Votre nom (imprimé sur les reçus comme encaisseur)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _current,
          obscureText: !_show,
          autofocus: true,
          decoration: _decoration('Mot de passe actuel'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _new,
          obscureText: !_show,
          decoration: _decoration('Nouveau mot de passe')
              .copyWith(helperText: '$kMinPasswordLength caractères minimum'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirm,
          obscureText: !_show,
          onSubmitted: (_) => _submit(),
          decoration: _decoration('Confirmer le nouveau mot de passe'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            ?widget.extraAction,
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy ? 'Enregistrement…' : 'Changer le mot de passe',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showChangePasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Changer mon mot de passe'),
      content: SizedBox(
        width: 420,
        child: ChangePasswordForm(
          extraAction: TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          onDone: () {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mot de passe modifié.')),
            );
          },
        ),
      ),
    ),
  );
}

/// Shown instead of the app until the user has chosen their own password
/// (first login of the default account, or after an administrator reset).
class ForcedPasswordChangeScreen extends ConsumerWidget {
  const ForcedPasswordChangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SchoolLogo(size: 72)),
                    const SizedBox(height: 16),
                    Text(
                      'Choisissez votre mot de passe',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bonjour ${user?.fullName ?? ''}. Pour votre sécurité, remplacez le '
                      'mot de passe provisoire par le vôtre avant de continuer.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    ChangePasswordForm(
                      initialName: user?.fullName ?? '',
                      extraAction: TextButton(
                        onPressed: () =>
                            ref.read(authProvider.notifier).logout(),
                        child: const Text('Se déconnecter'),
                      ),
                      onDone: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit a display name: your own (from the menu) or, for an administrator or
/// the Direction, the name of a cashier / administrator. Returns the new name.
Future<String?> showEditNameDialog(
  BuildContext context, {
  required String initialName,
  String title = 'Modifier mon nom',
}) {
  final controller = TextEditingController(text: initialName);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(
            labelText: 'Nom complet',
            helperText: 'Ce nom est imprimé sur les reçus comme encaisseur.',
            helperMaxLines: 2,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
