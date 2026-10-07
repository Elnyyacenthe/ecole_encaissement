import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/cancel_dialog.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../models/classe.dart';
import '../../models/student.dart';
import '../../providers/data_providers.dart';
import '../../providers/db_providers.dart';
import '../../repositories/students_repository.dart';

class StudentFormScreen extends ConsumerWidget {
  final int? studentId;
  const StudentFormScreen({super.key, this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(classesProvider);
    final year = ref.watch(activeSchoolYearProvider);
    final existing = studentId == null
        ? null
        : ref.watch(studentProvider(studentId!));

    return PageScaffold(
      title: studentId == null ? 'Nouvel élève' : "Modifier l'élève",
      subtitle: studentId == null
          ? 'Le matricule est généré automatiquement à l\'enregistrement'
          : null,
      child: AsyncValueView(
        value: classes,
        data: (classList) => AsyncValueView(
          value: year,
          data: (activeYear) {
            if (activeYear == null) {
              return const Center(child: Text('Aucune année scolaire active.'));
            }
            if (existing == null) {
              return _StudentForm(
                classes: classList,
                yearId: activeYear.id,
                yearLabel: activeYear.label,
              );
            }
            return AsyncValueView(
              value: existing,
              data: (s) => s == null
                  ? const Center(child: Text('Élève introuvable.'))
                  : _StudentForm(
                      classes: classList,
                      yearId: s.student.schoolYearId,
                      yearLabel: s.schoolYearLabel,
                      existing: s,
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _StudentForm extends ConsumerStatefulWidget {
  final List<Classe> classes;
  final int yearId;
  final String yearLabel;
  final StudentWithClasse? existing;

  const _StudentForm({
    required this.classes,
    required this.yearId,
    required this.yearLabel,
    this.existing,
  });

  @override
  ConsumerState<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends ConsumerState<_StudentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late int? _classeId;
  late DateTime _date;
  bool _saving = false;

  // État civil, parents et informations de sécurité — repris de la fiche
  // d'inscription papier.
  DateTime? _dateNaissance;
  late final TextEditingController _lieuNaissance;
  late final TextEditingController _nomPere;
  late final TextEditingController _professionPere;
  late final TextEditingController _nomMere;
  late final TextEditingController _professionMere;
  late final TextEditingController _adresseParents;
  late final TextEditingController _contact1;
  late final TextEditingController _contact2;
  Timer? _duplicateDebounce;
  List<StudentWithClasse> _duplicates = const [];

  /// Set when re-enrolling a former student found via the "ancien élève"
  /// search instead of creating a brand-new one: their existing row gets
  /// updated in place (same matricule) rather than a new row being created.
  StudentWithClasse? _reactivating;

  @override
  void initState() {
    super.initState();
    final e = widget.existing?.student;
    _name = TextEditingController(text: e?.fullName ?? '')
      ..addListener(_scheduleDuplicateCheck);
    _classeId = widget.existing?.student.classeId;
    _date = e?.dateInscription ?? DateTime.now();
    _dateNaissance = e?.dateNaissance;
    _lieuNaissance = TextEditingController(text: e?.lieuNaissance ?? '');
    _nomPere = TextEditingController(text: e?.nomPere ?? '');
    _professionPere = TextEditingController(text: e?.professionPere ?? '');
    _nomMere = TextEditingController(text: e?.nomMere ?? '');
    _professionMere = TextEditingController(text: e?.professionMere ?? '');
    _adresseParents = TextEditingController(text: e?.adresseParents ?? '');
    _contact1 = TextEditingController(text: e?.contactUrgence1 ?? '');
    _contact2 = TextEditingController(text: e?.contactUrgence2 ?? '');
    _scheduleDuplicateCheck();
  }

  @override
  void dispose() {
    _duplicateDebounce?.cancel();
    _name.dispose();
    _lieuNaissance.dispose();
    _nomPere.dispose();
    _professionPere.dispose();
    _nomMere.dispose();
    _professionMere.dispose();
    _adresseParents.dispose();
    _contact1.dispose();
    _contact2.dispose();
    super.dispose();
  }

  void _scheduleDuplicateCheck() {
    _duplicateDebounce?.cancel();
    _duplicateDebounce = Timer(
      const Duration(milliseconds: 400),
      _checkDuplicates,
    );
  }

  Future<void> _checkDuplicates() async {
    if (normalizeName(_name.text).isEmpty) {
      if (mounted && _duplicates.isNotEmpty) {
        setState(() => _duplicates = const []);
      }
      return;
    }
    try {
      final matches = await ref
          .read(studentsRepositoryProvider)
          .findByExactName(
            fullName: _name.text,
            schoolYearId: widget.yearId,
            excludeId: widget.existing?.student.id,
          );
      if (mounted) setState(() => _duplicates = matches);
    } catch (_) {
      // This is only a heads-up; the database itself still enforces the
      // rule on save, so a failed lookup must not block the form.
    }
  }

  List<StudentWithClasse> get _sameClassDuplicates =>
      _duplicates.where((d) => d.student.classeId == _classeId).toList();

  Classe? get _classe =>
      widget.classes.where((c) => c.id == _classeId).firstOrNull;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Loads a former student picked from the "ancien élève" search into the
  /// form: same matricule and identity, but the class must be re-confirmed
  /// (repeats or moves up) since it's for the new active year.
  void _applyFormerStudent(StudentWithClasse s) {
    final e = s.student;
    setState(() {
      _reactivating = s;
      _name.text = e.fullName;
      _classeId = e.classeId;
      _dateNaissance = e.dateNaissance;
      _lieuNaissance.text = e.lieuNaissance ?? '';
      _nomPere.text = e.nomPere ?? '';
      _professionPere.text = e.professionPere ?? '';
      _nomMere.text = e.nomMere ?? '';
      _professionMere.text = e.professionMere ?? '';
      _adresseParents.text = e.adresseParents ?? '';
      _contact1.text = e.contactUrgence1 ?? '';
      _contact2.text = e.contactUrgence2 ?? '';
    });
    _checkDuplicates();
  }

  void _clearReactivation() {
    setState(() {
      _reactivating = null;
      _name.clear();
      _classeId = null;
      _dateNaissance = null;
      _lieuNaissance.clear();
      _nomPere.clear();
      _professionPere.clear();
      _nomMere.clear();
      _professionMere.clear();
      _adresseParents.clear();
      _contact1.clear();
      _contact2.clear();
    });
  }

  Future<void> _pickFormerStudent() async {
    final picked = await showDialog<StudentWithClasse>(
      context: context,
      builder: (_) => const _FormerStudentDialog(),
    );
    if (picked != null) _applyFormerStudent(picked);
  }

  Future<void> _pickDateNaissance() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateNaissance ?? DateTime(DateTime.now().year - 6),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateNaissance = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(studentsRepositoryProvider);
    try {
      final existing = widget.existing;
      final reactivating = _reactivating;
      if (existing == null && reactivating != null) {
        await repo.reactivate(
          studentId: reactivating.student.id,
          classeId: _classeId!,
          schoolYearId: widget.yearId,
          dateInscription: _date,
          fullName: _name.text,
          dateNaissance: _dateNaissance,
          lieuNaissance: _lieuNaissance.text,
          nomPere: _nomPere.text,
          professionPere: _professionPere.text,
          nomMere: _nomMere.text,
          professionMere: _professionMere.text,
          adresseParents: _adresseParents.text,
          contactUrgence1: _contact1.text,
          contactUrgence2: _contact2.text,
        );
        ref.invalidate(studentsProvider);
        ref.invalidate(dashboardStatsProvider);
        final reactivated = await repo.getById(reactivating.student.id);
        if (!mounted) return;
        await _showCreated(reactivated!, reactivated: true);
      } else if (existing == null) {
        final id = await repo.create(
          fullName: _name.text,
          classeId: _classeId!,
          schoolYearId: widget.yearId,
          dateInscription: _date,
          dateNaissance: _dateNaissance,
          lieuNaissance: _lieuNaissance.text,
          nomPere: _nomPere.text,
          professionPere: _professionPere.text,
          nomMere: _nomMere.text,
          professionMere: _professionMere.text,
          adresseParents: _adresseParents.text,
          contactUrgence1: _contact1.text,
          contactUrgence2: _contact2.text,
        );
        ref.invalidate(studentsProvider);
        ref.invalidate(dashboardStatsProvider);
        final created = await repo.getById(id);
        if (!mounted) return;
        await _showCreated(created!);
      } else {
        await repo.update(
          id: existing.student.id,
          fullName: _name.text,
          classeId: _classeId!,
          dateInscription: _date,
          dateNaissance: _dateNaissance,
          lieuNaissance: _lieuNaissance.text,
          nomPere: _nomPere.text,
          professionPere: _professionPere.text,
          nomMere: _nomMere.text,
          professionMere: _professionMere.text,
          adresseParents: _adresseParents.text,
          contactUrgence1: _contact1.text,
          contactUrgence2: _contact2.text,
        );
        ref.invalidate(studentsProvider);
        ref.invalidate(studentProvider(existing.student.id));
        ref.invalidate(studentSituationProvider(existing.student.id));
        if (!mounted) return;
        context.go('/students');
      }
    } on StudentException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCreated(StudentWithClasse s, {bool reactivated = false}) async {
    final pay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(reactivated ? 'Élève réinscrit' : 'Élève enregistré'),
        content: Text(
          reactivated
              ? '${s.student.fullName}\nMatricule conservé : ${s.student.matricule}'
              : '${s.student.fullName}\nMatricule : ${s.student.matricule}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour à la liste'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Encaisser l'inscription"),
          ),
        ],
      ),
    );
    if (!mounted) return;
    context.go(pay == true ? '/payments?student=${s.student.id}' : '/students');
  }

  @override
  Widget build(BuildContext context) {
    final classe = _classe;
    final isNew = widget.existing == null;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      if (isNew && _reactivating == null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _pickFormerStudent,
                            icon: const Icon(Icons.history_outlined),
                            label: const Text("C'est un ancien élève ?"),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_reactivating != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.green.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.history_outlined,
                                color: AppColors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Réinscription d\'un ancien élève (${_reactivating!.schoolYearLabel}) '
                                  '— son matricule ${_reactivating!.student.matricule} sera conservé.',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              TextButton(
                                onPressed: _clearReactivation,
                                child: const Text('Annuler'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: ValueKey(
                          'matricule-${_reactivating?.student.matricule ?? widget.existing?.student.matricule ?? 'new'}',
                        ),
                        initialValue:
                            _reactivating?.student.matricule ??
                            widget.existing?.student.matricule ??
                            'Généré automatiquement',
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Matricule',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: "Nom de l'enfant",
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Le nom est obligatoire'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _classeId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Salle de classe',
                          helperText: _reactivating == null
                              ? null
                              : 'Confirmez : reprend la même classe, ou passe à la suivante.',
                          helperMaxLines: 2,
                        ),
                        items: [
                          for (final c in widget.classes)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                '${c.name}  (${c.section.label} - ${c.niveau.label})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _classeId = v);
                          _checkDuplicates();
                        },
                        validator: (v) =>
                            v == null ? 'Choisissez une classe' : null,
                      ),
                      if (_duplicates.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DuplicateWarning(
                          sameClass: _sameClassDuplicates,
                          otherClasses: _duplicates
                              .where((d) => d.student.classeId != _classeId)
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Niveau scolaire',
                              ),
                              child: Text(classe?.niveau.label ?? '-'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Section',
                              ),
                              child: Text(classe?.section.label ?? '-'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Année scolaire',
                        ),
                        child: Text(widget.yearLabel),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Date d'inscription",
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(formatDate(_date)),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _SectionTitle('État civil'),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDateNaissance,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Date de naissance',
                                  suffixIcon: Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                  ),
                                ),
                                child: Text(
                                  _dateNaissance == null
                                      ? '-'
                                      : formatDate(_dateNaissance!),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _lieuNaissance,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Lieu de naissance',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle('Parents ou tuteur'),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nomPere,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nom du père',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _professionPere,
                              decoration: const InputDecoration(
                                labelText: 'Profession',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nomMere,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nom de la mère',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _professionMere,
                              decoration: const InputDecoration(
                                labelText: 'Profession',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _adresseParents,
                        decoration: const InputDecoration(
                          labelText: 'Adresse des parents ou tuteur',
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle('Contacts susceptibles de chercher l\'enfant'),
                      const SizedBox(height: 4),
                      const Text(
                        'Si vous êtes empêché — au moins un des deux.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _contact1,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Contact 1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _contact2,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Contact 2',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          FilledButton(
                            onPressed:
                                _saving || _sameClassDuplicates.isNotEmpty
                                ? null
                                : _save,
                            child: Text(
                              isNew ? "Enregistrer l'élève" : 'Enregistrer',
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => context.go('/students'),
                            child: const Text('Annuler'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search dialog for the "ancien élève" flow: finds anyone not properly
/// settled into the active year yet — no row there at all (left without
/// being promoted, possibly years ago), or a "provisoire" row Promotion
/// created that nobody confirmed — so their existing fiche and matricule
/// get reused/confirmed instead of piling up a new one.
class _FormerStudentDialog extends ConsumerStatefulWidget {
  const _FormerStudentDialog();

  @override
  ConsumerState<_FormerStudentDialog> createState() =>
      _FormerStudentDialogState();
}

class _FormerStudentDialogState extends ConsumerState<_FormerStudentDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(formerStudentSearchProvider(_query));
    return AlertDialog(
      title: const Text('Rechercher un ancien élève'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            const Text(
              'Élèves à réinscrire ou à confirmer : ceux qui ne sont pas '
              "revenus l'année suivante, et ceux marqués \"PROVISOIRE\" "
              "(promus en masse, jamais confirmés).",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filtrer par nom ou matricule (optionnel)',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        _query.trim().isEmpty
                            ? "Aucun ancien élève en attente de réinscription."
                            : 'Aucun résultat pour "$_query".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final s in list)
                        ListTile(
                          title: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(s.student.fullName)),
                              if (!s.student.confirme) ...[
                                const SizedBox(width: 8),
                                const CancelledBadge(
                                  label: 'PROVISOIRE',
                                  color: AppColors.gold,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${s.student.matricule} - ${s.classeName} '
                            '(${s.schoolYearLabel})',
                          ),
                          onTap: () => Navigator.pop(context, s),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shown under the class field: a hard block for an exact same-class
/// duplicate, a soft heads-up for a same-name student in another class.
class _DuplicateWarning extends StatelessWidget {
  final List<StudentWithClasse> sameClass;
  final List<StudentWithClasse> otherClasses;
  const _DuplicateWarning({
    required this.sameClass,
    required this.otherClasses,
  });

  @override
  Widget build(BuildContext context) {
    final blocking = sameClass.isNotEmpty;
    final matches = blocking ? sameClass : otherClasses;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blocking ? const Color(0xFFFDECEA) : const Color(0xFFFFF6E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: blocking ? const Color(0xFFF0B4AC) : const Color(0xFFF0D690),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocking ? Icons.block : Icons.warning_amber_rounded,
            size: 18,
            color: blocking ? AppColors.danger : const Color(0xFF9A7B1E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blocking
                      ? 'Un élève portant exactement ce nom existe déjà dans cette classe.'
                      : 'Un élève portant exactement ce nom existe dans une autre classe.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final d in matches)
                  Text(
                    '${d.student.matricule} - ${d.classeName} '
                    '(${d.schoolYearLabel})',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                if (!blocking)
                  const Text(
                    "Vérifiez qu'il ne s'agit pas d'un doublon avant d'enregistrer.",
                    style: TextStyle(fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
