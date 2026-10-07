import '../core/db/mysql_connection_service.dart';
import '../core/db/sequence_service.dart';
import '../models/cancellation.dart';
import '../models/invoice_summary.dart';
import '../models/payment.dart';
import '../models/payment_situation.dart';
import '../models/receipt_data.dart';
import '../models/tariff.dart';
import 'students_repository.dart';

class PaymentException implements Exception {
  final String message;
  PaymentException(this.message);
  @override
  String toString() => message;
}

int _int(Object? v) => (v as num).toInt();

const _situationSql = '''
SELECT t.poste, t.montant, t.date_limite,
  CAST(COALESCE((SELECT SUM(p.montant_paye) FROM payments p
                 WHERE p.student_id = s.id AND p.poste = t.poste AND p.annule = 0
                 __UP_TO__), 0) AS SIGNED) AS paid
FROM students s
JOIN classes c ON c.id = s.classe_id
JOIN tariffs t ON t.school_year_id = s.school_year_id AND t.niveau = c.level
WHERE s.id = ?
ORDER BY FIELD(t.poste,'INSCRIPTION','TRANCHE1','TRANCHE2','TRANCHE3')
''';

const _paymentColumns =
    'id, invoice_number, student_id, poste, montant_paye, date_paiement, created_at, operateur, '
    'annule, annule_par, annule_le, motif_annulation';

StudentSituation _buildSituation(Iterable<Map<String, dynamic>> rows) =>
    StudentSituation(
      postes: [
        for (final r in rows)
          PosteSituation(
            poste: Poste.fromDb(r['poste'].toString()),
            montantDu: _int(r['montant']),
            montantPaye: _int(r['paid']),
            dateLimite: r['date_limite'] as DateTime?,
          ),
      ],
    );

class PaymentsRepository {
  final MySqlConnectionService db;
  final StudentsRepository students;
  PaymentsRepository(this.db, this.students);

  /// Full-year situation for a student. With [upToPaymentId], payments with a
  /// higher id are ignored (used to reproduce a receipt as it was issued).
  Future<StudentSituation> situationFor(
    int studentId, {
    int? upToPaymentId,
  }) async {
    final rows = await db.select(
      _situationSql.replaceFirst(
        '__UP_TO__',
        upToPaymentId == null ? '' : 'AND p.id <= ?',
      ),
      [?upToPaymentId, studentId],
    );
    return _buildSituation(rows);
  }

  /// The student's invoices, newest first. One deposit spread over several
  /// postes is one invoice with several lines.
  Future<List<Invoice>> invoicesForStudent(int studentId) async {
    final rows = await db.select(
      'SELECT $_paymentColumns FROM payments WHERE student_id = ? ORDER BY id DESC',
      [studentId],
    );
    return Invoice.group(rows.map(Payment.fromRow));
  }

  /// All invoices, newest first, optionally filtered by a text (student name,
  /// matricule or exact invoice number) and by payment date (inclusive).
  Future<List<InvoiceSummary>> history({
    String query = '',
    DateTime? from,
    DateTime? to,
    int limit = 3000,
  }) async {
    final where = <String>[];
    final params = <Object?>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add(
        '(s.full_name LIKE ? OR s.matricule LIKE ? OR p.invoice_number = ?)',
      );
      params
        ..add('%$q%')
        ..add('%$q%')
        ..add(int.tryParse(q) ?? -1);
    }
    if (from != null) {
      where.add('p.date_paiement >= ?');
      params.add(toDbDate(from));
    }
    if (to != null) {
      where.add('p.date_paiement <= ?');
      params.add(toDbDate(to));
    }
    final rows = await db.select('''
SELECT p.id, p.invoice_number, p.poste, p.montant_paye, p.date_paiement, p.created_at,
       p.operateur, p.annule, p.annule_par, p.annule_le, p.motif_annulation,
       s.id AS student_id, s.matricule, s.full_name, c.name AS classe_name
FROM payments p
JOIN students s ON s.id = p.student_id
JOIN classes c ON c.id = s.classe_id
${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
ORDER BY p.invoice_number DESC, p.id
LIMIT $limit
''', params);

    final byInvoice = <int, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byInvoice.putIfAbsent(_int(r['invoice_number']), () => []).add(r);
    }
    return [
      for (final e in byInvoice.entries)
        InvoiceSummary(
          invoiceNumber: e.key,
          firstPaymentId: _int(e.value.first['id']),
          studentId: _int(e.value.first['student_id']),
          matricule: e.value.first['matricule'] as String,
          fullName: e.value.first['full_name'] as String,
          classeName: e.value.first['classe_name'] as String,
          datePaiement: e.value.first['date_paiement'] as DateTime,
          createdAt: e.value.first['created_at'] as DateTime,
          operateur: e.value.first['operateur'] as String,
          cancellation: Cancellation.fromRow(e.value.first),
          lines: [
            for (final r in e.value)
              PosteAllocation(
                Poste.fromDb(r['poste'] as String),
                _int(r['montant_paye']),
              ),
          ],
        ),
    ];
  }

  /// Records a deposit and returns the id of the first row of its invoice
  /// (usable to open the receipt).
  ///
  /// The amount is spread over the unpaid postes — [poste] first, then the
  /// others in order (see [StudentSituation.allocate]) — and may not exceed
  /// the total still owed for the year. The student row is locked so two PCs
  /// cannot both pass that check for the same student; the invoice number
  /// comes from the global counter inside the same transaction.
  Future<int> record({
    required int studentId,
    required Poste poste,
    required int montant,
    required DateTime datePaiement,
    required String operateur,
  }) {
    if (montant <= 0) {
      throw PaymentException('Le montant doit être supérieur à 0.');
    }
    if (operateur.trim().isEmpty) {
      throw PaymentException("Le nom de l'opérateur est obligatoire.");
    }
    return db.transaction((ctx) async {
      final locked = await ctx.query(
        'SELECT annule, confirme FROM students WHERE id = ? FOR UPDATE',
        [studentId],
      );
      if (locked.isEmpty) {
        throw PaymentException('Élève introuvable.');
      }
      if ((locked.first['annule'] as int) == 1) {
        throw PaymentException(
          'Cette inscription a été annulée ; aucun encaissement ne peut y être ajouté.',
        );
      }
      // A student promoted in bulk is provisional until proven — a real
      // payment is exactly that proof, so it confirms them automatically.
      if ((locked.first['confirme'] as int) == 0) {
        await ctx.query('UPDATE students SET confirme = 1 WHERE id = ?', [
          studentId,
        ]);
      }

      final rows = await ctx.query(
        _situationSql.replaceFirst('__UP_TO__', ''),
        [studentId],
      );
      final situation = _buildSituation(rows.map((r) => r.fields));
      if (situation.postes.isEmpty) {
        throw PaymentException(
          'Aucun tarif défini pour cet élève (voir écran Tarifs).',
        );
      }
      if (situation.totalReste <= 0) {
        throw PaymentException(
          "Tous les postes de l'année sont déjà soldés pour cet élève.",
        );
      }
      final split = situation.allocate(montant, startWith: poste);
      if (split.leftover > 0) {
        throw PaymentException(
          'Le montant dépasse le total restant à payer pour l\'année '
          '(${situation.totalReste} FCFA).',
        );
      }

      final invoice = await SequenceService.nextInvoiceNumber(ctx);
      int? firstId;
      for (final part in split.parts) {
        final res = await ctx.query(
          'INSERT INTO payments (invoice_number, student_id, poste, montant_paye, date_paiement, operateur) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            invoice,
            studentId,
            part.poste.dbValue,
            part.montant,
            toDbDate(datePaiement),
            operateur.trim(),
          ],
        );
        firstId ??= res.insertId!;
      }
      return firstId!;
    });
  }

  /// Receipt of the invoice that contains [paymentId].
  Future<ReceiptData?> receiptData(int paymentId) async {
    final head = await db.select(
      'SELECT invoice_number FROM payments WHERE id = ?',
      [paymentId],
    );
    if (head.isEmpty) return null;

    final rows = await db.select(
      'SELECT $_paymentColumns FROM payments WHERE invoice_number = ? '
      "ORDER BY FIELD(poste,'INSCRIPTION','TRANCHE1','TRANCHE2','TRANCHE3')",
      [head.first['invoice_number']],
    );
    final payments = rows.map(Payment.fromRow).toList();
    final first = payments.first;
    final lastId = payments.map((p) => p.id).reduce((a, b) => a > b ? a : b);

    final student = await students.getById(first.studentId);
    if (student == null) return null;
    final situation = await situationFor(
      first.studentId,
      upToPaymentId: lastId,
    );
    final day = await db.select(
      'SELECT CAST(COALESCE(SUM(montant_paye), 0) AS SIGNED) AS total FROM payments '
      'WHERE student_id = ? AND date_paiement = ? AND id <= ? AND annule = 0',
      [first.studentId, first.datePaiement, lastId],
    );
    return ReceiptData(
      invoiceNumber: first.invoiceNumber,
      datePaiement: first.datePaiement,
      createdAt: first.createdAt,
      operateur: first.operateur,
      student: student,
      lines: ReceiptData.buildLines(payments, situation),
      situation: situation,
      totalPayeCeJour: _int(day.first['total']),
      cancellation: first.cancellation,
    );
  }

  /// Cancels every line of an invoice — the rows are kept forever (same
  /// "cancel, never delete, always visible" rule as
  /// [StudentsRepository.cancel]); the amounts stop counting towards the
  /// student's situation and the unpaid report, but the invoice stays visible
  /// in the history and on any reprinted receipt, clearly marked as annulée.
  Future<void> cancelInvoice({
    required int invoiceNumber,
    required String cancelledBy,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw PaymentException("Le motif d'annulation est obligatoire.");
    }
    final rows = await db.select(
      'SELECT annule FROM payments WHERE invoice_number = ?',
      [invoiceNumber],
    );
    if (rows.isEmpty) throw PaymentException('Facture introuvable.');
    if ((rows.first['annule'] as int) == 1) {
      throw PaymentException('Cette facture est déjà annulée.');
    }
    await db.execute(
      'UPDATE payments SET annule = 1, annule_par = ?, annule_le = NOW(), '
      'motif_annulation = ? WHERE invoice_number = ?',
      [cancelledBy, reason.trim(), invoiceNumber],
    );
  }
}
