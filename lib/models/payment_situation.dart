import 'tariff.dart';

/// Financial status for a single poste (inscription or one tranche):
/// how much is due, how much has been paid so far, and the remainder.
class PosteSituation {
  final Poste poste;
  final int montantDu;
  final int montantPaye;
  final DateTime? dateLimite;

  const PosteSituation({
    required this.poste,
    required this.montantDu,
    required this.montantPaye,
    this.dateLimite,
  });

  int get resteAPayer => (montantDu - montantPaye).clamp(0, montantDu);
  bool get estSolde => montantPaye >= montantDu;
}

/// Full-year financial situation for a student: one line per poste plus
/// the grand total, shown immediately after recording a payment.
class StudentSituation {
  final List<PosteSituation> postes;

  const StudentSituation({required this.postes});

  int get totalDu => postes.fold(0, (sum, p) => sum + p.montantDu);
  int get totalPaye => postes.fold(0, (sum, p) => sum + p.montantPaye);
  int get totalReste => postes.fold(0, (sum, p) => sum + p.resteAPayer);

  PosteSituation forPoste(Poste poste) =>
      postes.firstWhere((p) => p.poste == poste);

  /// The first poste (in inscription -> tranche 3 order) not yet fully paid.
  PosteSituation? get firstOpen => postes.where((p) => !p.estSolde).firstOrNull;

  /// Splits a deposit over the unpaid postes: [startWith] first, then the
  /// others in their natural order, each capped at what it still owes.
  /// E.g. 50 000 F with inscription 34 000 open -> inscription 34 000 +
  /// 1st tranche 16 000. Any amount above [totalReste] is left over and
  /// must be rejected by the caller.
  ({List<PosteAllocation> parts, int leftover}) allocate(
    int montant, {
    Poste? startWith,
  }) {
    final open = postes.where((p) => !p.estSolde).toList();
    final start = open.where((p) => p.poste == startWith).firstOrNull;
    final ordered = [?start, ...open.where((p) => p != start)];

    final parts = <PosteAllocation>[];
    var remaining = montant;
    for (final p in ordered) {
      if (remaining <= 0) break;
      final part = remaining < p.resteAPayer ? remaining : p.resteAPayer;
      parts.add(PosteAllocation(p.poste, part));
      remaining -= part;
    }
    return (parts: parts, leftover: remaining);
  }
}

class PosteAllocation {
  final Poste poste;
  final int montant;
  const PosteAllocation(this.poste, this.montant);
}
