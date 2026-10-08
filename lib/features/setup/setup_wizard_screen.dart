import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/classe.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import '../../repositories/settings_repository.dart';

class _WizardClasse {
  String name;
  final Section section;
  final Niveau niveau;
  _WizardClasse(this.name, this.section, this.niveau);
}

/// First-launch configuration — shown instead of the normal app until an
/// Admin/Direction account completes it (or, for an installation that
/// already had classes before this existed, it is marked done
/// automatically — see [bootstrapDatabase]). Everything here stays
/// editable afterwards from Paramètres and Classes.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  final _name = TextEditingController();
  final _box = TextEditingController();
  final _phone = TextEditingController();
  final _prefix = TextEditingController(text: 'MP');
  final Set<Section> _sections = {Section.francophone};
  List<_WizardClasse> _classes = [];
  Uint8List? _logo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rebuildClasses();
  }

  @override
  void dispose() {
    _name.dispose();
    _box.dispose();
    _phone.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _rebuildClasses() {
    _classes = [
      for (final c in Classe.seedData)
        if (_sections.contains(c.section))
          _WizardClasse(c.name, c.section, c.niveau),
    ];
  }

  Future<void> _pickLogo() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _logo = bytes);
  }

  Future<void> _finish() async {
    final name = _name.text.trim();
    final prefix = _prefix.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = "Le nom de l'établissement est obligatoire.");
      return;
    }
    if (_sections.isEmpty) {
      setState(() => _error = 'Choisissez au moins une section.');
      return;
    }
    if (prefix.isEmpty) {
      setState(() => _error = 'Le préfixe matricule est obligatoire.');
      return;
    }
    final names = _classes.map((c) => c.name.trim()).toList();
    if (names.any((n) => n.isEmpty)) {
      setState(() => _error = 'Toutes les classes doivent avoir un nom.');
      return;
    }
    if (names.isEmpty) {
      setState(() => _error = 'Ajoutez au moins une classe.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final classesRepo = ref.read(classesRepositoryProvider);
      await settings.setText(SettingsRepository.keySchoolName, name);
      await settings.setText(SettingsRepository.keySchoolBox, _box.text);
      await settings.setText(SettingsRepository.keySchoolPhone, _phone.text);
      await settings.setText(SettingsRepository.keyMatriculePrefix, prefix);
      if (_logo != null) await settings.saveLogo(_logo!);
      for (final c in _classes) {
        await classesRepo.create(
          name: c.name.trim(),
          section: c.section,
          niveau: c.niveau,
        );
      }
      await settings.markSetupCompleted();
      ref.invalidate(setupCompletedProvider);
      ref.invalidate(schoolIdentityProvider);
      ref.invalidate(classesProvider);
      ref.invalidate(logoBytesProvider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider);
    if (me == null || !me.role.hasAdminRights) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Cette installation n'est pas encore configurée. Demandez à "
              "un administrateur ou à la Direction de se connecter pour "
              'terminer la configuration.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuration de votre établissement',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'À faire une seule fois — tout reste modifiable '
                      'ensuite depuis Paramètres et Classes.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Nom de l'établissement",
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _box,
                            decoration: const InputDecoration(
                              labelText: 'Boîte postale (optionnel)',
                              hintText: '4362 Yaoundé',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            decoration: const InputDecoration(
                              labelText: 'Téléphone (optionnel)',
                              hintText: '+237677758166',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _prefix,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Préfixe matricule',
                              helperText: 'Ex. "MP" -> 26MP001',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              _logo == null
                                  ? 'Choisir le logo (optionnel)'
                                  : 'Logo sélectionné ✓',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sections',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in Section.values)
                          FilterChip(
                            label: Text(s.label),
                            selected: _sections.contains(s),
                            onSelected: (v) => setState(() {
                              v ? _sections.add(s) : _sections.remove(s);
                              _rebuildClasses();
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Classes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _sections.isEmpty
                              ? null
                              : () => setState(() {
                                  _classes.add(
                                    _WizardClasse(
                                      '',
                                      _sections.first,
                                      Niveau.primaire,
                                    ),
                                  );
                                }),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter une classe'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Préremplies à partir du modèle COSBIMP selon les '
                      'sections choisies — renommez, supprimez ou ajoutez '
                      'librement avant de valider.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_classes.isEmpty)
                      const Text(
                        'Choisissez au moins une section ci-dessus pour '
                        'voir les classes proposées.',
                        style: TextStyle(color: AppColors.textMuted),
                      )
                    else
                      Column(
                        children: [
                          for (var i = 0; i < _classes.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: _classes[i].name,
                                      onChanged: (v) => _classes[i].name = v,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 140,
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        isDense: true,
                                      ),
                                      child: Text(
                                        '${_classes[i].section.label} - '
                                        '${_classes[i].niveau.label}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Retirer',
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        setState(() => _classes.removeAt(i)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _finish,
                        icon: const Icon(Icons.check),
                        label: Text(
                          _saving
                              ? 'Enregistrement…'
                              : 'Terminer la configuration',
                        ),
                      ),
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
