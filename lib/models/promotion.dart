import 'classe.dart';

/// One student of the source year, proposed for promotion into the target
/// year. [suggestedClasseId] is the classe that naturally follows their
/// current one in the same section, or null when they are in the last
/// classe of that section (nothing to suggest: a graduating "sortant").
class PromotionCandidate {
  final int studentId;
  final String matricule;
  final String fullName;
  final int currentClasseId;
  final String currentClasseName;
  final Section section;
  final Niveau niveau;
  final int? suggestedClasseId;

  const PromotionCandidate({
    required this.studentId,
    required this.matricule,
    required this.fullName,
    required this.currentClasseId,
    required this.currentClasseName,
    required this.section,
    required this.niveau,
    required this.suggestedClasseId,
  });
}

/// The operator's final decision for one candidate: which classe to enrol
/// them in for the target year, or null to leave them out (redoublant kept
/// out on purpose, sortant, or already handled another way).
class PromotionSelection {
  final int studentId;
  final String fullName;
  final int? targetClasseId;

  const PromotionSelection({
    required this.studentId,
    required this.fullName,
    this.targetClasseId,
  });
}

class PromotionResult {
  final int promoted;
  final List<String> failures;

  const PromotionResult({required this.promoted, required this.failures});
}
