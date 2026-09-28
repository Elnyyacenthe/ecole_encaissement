import '../models/classe.dart';
import '../models/tariff.dart';

/// Every label printed on a receipt, in one language. The receipt language
/// follows the student's section: Francophone -> French, Anglophone -> English.
class ReceiptLabels {
  final String schoolName;
  final String address;
  final String phone;
  final String title;
  final String invoiceNumber;
  final String dateTime;
  final String operator;
  final String student;
  final String matricule;
  final String classe;
  final String niveau;
  final String item;
  final String netAPayer;
  final String montantPaye;
  final String difference;
  final String resteSurAnnee;
  final String dueDate;
  final String totalPaidToday;
  final String cancelledBanner;
  final String cancelledReason;
  final String Function(Poste) posteLabel;
  final String Function(Niveau) niveauLabel;

  const ReceiptLabels({
    required this.schoolName,
    required this.address,
    required this.phone,
    required this.title,
    required this.invoiceNumber,
    required this.dateTime,
    required this.operator,
    required this.student,
    required this.matricule,
    required this.classe,
    required this.niveau,
    required this.item,
    required this.netAPayer,
    required this.montantPaye,
    required this.difference,
    required this.resteSurAnnee,
    required this.dueDate,
    required this.totalPaidToday,
    required this.cancelledBanner,
    required this.cancelledReason,
    required this.posteLabel,
    required this.niveauLabel,
  });

  static ReceiptLabels forSection(Section section) =>
      section == Section.francophone ? fr : en;

  static const fr = ReceiptLabels(
    schoolName: 'Complexe Scolaire Bilingue Mariane et Paul',
    address: 'B.P. 4362 Yaoundé',
    phone: 'Tél. +237677758166',
    title: 'REÇU DE PAIEMENT',
    invoiceNumber: 'N° facture',
    dateTime: 'Date et heure',
    operator: 'Encaisseur',
    student: 'Élève',
    matricule: 'Matricule',
    classe: 'Salle de classe',
    niveau: 'Niveau scolaire',
    item: 'Objet du paiement',
    netAPayer: 'Net à payer',
    montantPaye: 'Montant payé',
    difference: 'Différence',
    resteSurAnnee: "Reste sur l'année",
    dueDate: 'Date limite',
    totalPaidToday: 'Total payé ce jour',
    cancelledBanner: 'FACTURE ANNULÉE - NE FAIT PLUS FOI',
    cancelledReason: 'Motif',
    posteLabel: _posteFr,
    niveauLabel: _niveauFr,
  );

  static const en = ReceiptLabels(
    schoolName: 'Complexe Scolaire Bilingue Mariane et Paul',
    address: 'P.O. Box 4362 Yaoundé',
    phone: 'Tel. +237677758166',
    title: 'PAYMENT RECEIPT',
    invoiceNumber: 'Invoice No.',
    dateTime: 'Date and time',
    operator: 'Cashier',
    student: 'Student',
    matricule: 'Registration No.',
    classe: 'Class',
    niveau: 'Level',
    item: 'Payment for',
    netAPayer: 'Amount due',
    montantPaye: 'Amount paid',
    difference: 'Balance',
    resteSurAnnee: 'Remaining for the year',
    dueDate: 'Due date',
    totalPaidToday: 'Total paid today',
    cancelledBanner: 'CANCELLED INVOICE - NO LONGER VALID',
    cancelledReason: 'Reason',
    posteLabel: _posteEn,
    niveauLabel: _niveauEn,
  );
}

String _posteFr(Poste p) => switch (p) {
  Poste.inscription => "Frais d'inscription",
  _ => 'Frais de scolarité - ${p.labelFr}',
};

String _posteEn(Poste p) => switch (p) {
  Poste.inscription => 'Registration fee',
  _ => 'School fees - ${p.labelEn}',
};

String _niveauFr(Niveau n) => n.label;

String _niveauEn(Niveau n) => switch (n) {
  Niveau.maternelle => 'Nursery',
  Niveau.primaire => 'Primary',
};
