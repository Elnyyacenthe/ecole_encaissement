import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/school_logo.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import 'backup_section.dart';
import 'users_section.dart';

class SchoolYearSettingsScreen extends ConsumerStatefulWidget {
  const SchoolYearSettingsScreen({super.key});

  @override
  ConsumerState<SchoolYearSettingsScreen> createState() => _State();
}

class _State extends ConsumerState<SchoolYearSettingsScreen> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(schoolYearsProvider);
    ref.invalidate(activeSchoolYearProvider);
  }

  Future<void> _create() async {
    try {
      await ref
          .read(schoolYearsRepositoryProvider)
          .createAndActivate(_label.text.trim());
      _label.clear();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(schoolYearsProvider);
    return PageScaffold(
      title: 'Paramètres',
      subtitle: "Logo, années scolaires, utilisateurs et sauvegardes",
      child: ListView(
        children: [
          const _LogoCard(),
          const SizedBox(height: 28),
          Text(
            'Années scolaires',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Créer une année copie les tarifs par défaut et la rend active. '
            'Les matricules repartent de 001 chaque année.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Nouvelle année',
                    hintText: '2027-2028',
                  ),
                  onSubmitted: (_) => _create(),
                ),
              ),
              FilledButton(
                onPressed: _create,
                child: const Text('Créer et activer'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AsyncValueView(
            value: years,
            data: (list) => Card(
              child: Column(
                children: [
                  for (final y in list)
                    ListTile(
                      leading: Icon(
                        y.isActive
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(y.label),
                      subtitle: y.isActive ? const Text('Année active') : null,
                      trailing: y.isActive
                          ? null
                          : TextButton(
                              onPressed: () async {
                                await ref
                                    .read(schoolYearsRepositoryProvider)
                                    .setActive(y.id);
                                _refresh();
                              },
                              child: const Text('Activer'),
                            ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const UsersSection(),
          const SizedBox(height: 32),
          const BackupSection(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Lets an administrator pick the school logo once; it is stored in the
/// database and used on every PC and on every printed document.
class _LogoCard extends ConsumerStatefulWidget {
  const _LogoCard();

  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _busy = false;

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
      ],
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveLogo(await file.readAsBytes());
      ref.invalidate(logoBytesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Logo enregistré.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 20,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: AppColors.border),
              ),
              child: const ClipOval(child: SchoolLogo(size: 88)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Logo de l'école",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Affiché dans le menu et imprimé sur les reçus et rapports, sur tous les postes.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Choisir le logo'),
            ),
          ],
        ),
      ),
    );
  }
}
