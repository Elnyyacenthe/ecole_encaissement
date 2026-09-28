import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/async_value_view.dart';
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

  Timer? _duplicateDebounce;
  List<StudentWithClasse> _duplicates = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.student.fullName ?? '')
      ..addListener(_scheduleDuplicateCheck);
    _classeId = e?.student.classeId;
    _date = e?.student.dateInscription ?? DateTime.now();
    _scheduleDuplicateCheck();
  }

  @override
  void dispose() {
    _duplicateDebounce?.cancel();
    _name.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(studentsRepositoryProvider);
    try {
      final existing = widget.existing;
      if (existing == null) {
        final id = await repo.create(
          fullName: _name.text,
          classeId: _classeId!,
          schoolYearId: widget.yearId,
          dateInscription: _date,
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

  Future<void> _showCreated(StudentWithClasse s) async {
    final pay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Élève enregistré'),
        content: Text(
          '${s.student.fullName}\nMatricule : ${s.student.matricule}',
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
                      TextFormField(
                        initialValue:
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
                        decoration: const InputDecoration(
                          labelText: 'Salle de classe',
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
