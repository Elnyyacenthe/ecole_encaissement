import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_view.dart';
import '../auth/change_password_form.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import '../../repositories/users_repository.dart';

/// Administrator tools: list of accounts, add one, reset a forgotten
/// password, deactivate / reactivate.
class UsersSection extends ConsumerWidget {
  const UsersSection({super.key});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      ref.invalidate(usersProvider);
      if (context.mounted) _snack(context, done);
    } on AuthException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } catch (e) {
      if (context.mounted) _snack(context, 'Erreur : $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final me = ref.watch(authProvider);
    if (me == null) return const SizedBox.shrink();
    final repo = ref.read(usersRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Utilisateurs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilledButton.icon(
              onPressed: () async {
                final data = await showDialog<_NewUser>(
                  context: context,
                  builder: (_) =>
                      _AddUserDialog(roles: me.role.manageableRoles),
                );
                if (data == null || !context.mounted) return;
                await _run(
                  context,
                  ref,
                  () => repo.create(
                    actor: me,
                    username: data.username,
                    fullName: data.fullName,
                    role: data.role,
                    temporaryPassword: data.password,
                  ),
                  'Utilisateur créé. Il choisira son mot de passe à la première connexion.',
                );
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Ajouter un utilisateur'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Direction : tous les droits. Administrateur : tarifs, paramètres et comptes caissier. Caissier : élèves, encaissement, historique, impayés.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: users,
          data: (list) => Card(
            child: Column(
              children: [
                for (final u in list)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: u.isActive
                          ? AppColors.navy
                          : AppColors.textMuted,
                      child: Text(
                        u.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      u.id == me.id ? '${u.fullName} (vous)' : u.fullName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: u.isActive ? null : AppColors.textMuted,
                      ),
                    ),
                    subtitle: Text(
                      '${u.username} - ${u.role.label}'
                      '${u.isActive ? '' : ' - désactivé'}'
                      '${u.mustChangePassword ? ' - doit changer son mot de passe' : ''}',
                    ),
                    trailing: !me.role.canManage(u.role)
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: 'Actions',
                            onSelected: (value) async {
                              if (value == 'name') {
                                final name = await showEditNameDialog(
                                  context,
                                  initialName: u.fullName,
                                  title: 'Nom de ${u.fullName}',
                                );
                                if (name == null || !context.mounted) return;
                                await _run(
                                  context,
                                  ref,
                                  () => repo.updateFullName(
                                    actor: me,
                                    userId: u.id,
                                    fullName: name,
                                  ),
                                  'Nom modifié.',
                                );
                              } else if (value == 'reset') {
                                final temp = await showDialog<String>(
                                  context: context,
                                  builder: (_) => _ResetPasswordDialog(user: u),
                                );
                                if (temp == null || !context.mounted) return;
                                await _run(
                                  context,
                                  ref,
                                  () => repo.resetPassword(me, u.id, temp),
                                  'Mot de passe provisoire enregistré pour ${u.fullName}.',
                                );
                              } else if (value == 'toggle') {
                                await _run(
                                  context,
                                  ref,
                                  () => repo.setActive(me, u.id, !u.isActive),
                                  u.isActive
                                      ? 'Compte désactivé.'
                                      : 'Compte réactivé.',
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'name',
                                child: Text('Modifier le nom'),
                              ),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Text('Réinitialiser le mot de passe'),
                              ),
                              if (u.id != me.id)
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    u.isActive ? 'Désactiver' : 'Réactiver',
                                  ),
                                ),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewUser {
  final String username;
  final String fullName;
  final UserRole role;
  final String password;
  const _NewUser(this.username, this.fullName, this.role, this.password);
}

class _AddUserDialog extends StatefulWidget {
  final List<UserRole> roles;
  const _AddUserDialog({required this.roles});

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late UserRole _role = widget.roles.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      UsersRepository.validateNewPassword(_password.text);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (_name.text.trim().isEmpty || _username.text.trim().isEmpty) {
      setState(() => _error = 'Renseignez le nom et l\'identifiant.');
      return;
    }
    Navigator.pop(
      context,
      _NewUser(_username.text, _name.text, _role, _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel utilisateur'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom complet'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Identifiant de connexion',
                  hintText: 'ex. marie',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [
                  for (final r in widget.roles)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => _role = r ?? _role),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe provisoire',
                  helperText:
                      'La personne devra le changer à sa première connexion. '
                      '$kMinPasswordLength caractères minimum.',
                  helperMaxLines: 2,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Créer')),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final AppUser user;
  const _ResetPasswordDialog({required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      UsersRepository.validateNewPassword(_password.text);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mot de passe de ${widget.user.fullName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe provisoire',
                helperText: 'Il devra être remplacé à la prochaine connexion.',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
