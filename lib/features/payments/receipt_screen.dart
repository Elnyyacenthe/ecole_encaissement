import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../pdf/pdf_assets.dart';
import '../../pdf/receipt_pdf_builder.dart';
import '../../providers/data_providers.dart';

class ReceiptScreen extends ConsumerWidget {
  final int paymentId;

  /// Opened from the history page: "back" returns there instead of to the cashier screen.
  final bool backToHistory;
  const ReceiptScreen({
    super.key,
    required this.paymentId,
    this.backToHistory = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(receiptDataProvider(paymentId));
    return PageScaffold(
      title: 'Reçu de paiement',
      subtitle: data.value == null
          ? null
          : 'Facture N° ${data.value!.invoiceNumber}',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            if (backToHistory) {
              context.go('/history');
              return;
            }
            final studentId = data.value?.student.student.id;
            context.go(
              studentId == null ? '/payments' : '/payments?student=$studentId',
            );
          },
          icon: const Icon(Icons.arrow_back),
          label: Text(
            backToHistory ? "Retour à l'historique" : "Retour à l'encaissement",
          ),
        ),
      ],
      child: AsyncValueView(
        value: data,
        data: (d) {
          if (d == null) {
            return const Center(child: Text('Paiement introuvable.'));
          }
          return Card(
            child: PdfPreview(
              canChangeOrientation: false,
              canChangePageFormat: false,
              initialPageFormat: receiptPageFormat(d),
              pdfFileName: 'recu_${d.invoiceNumber}.pdf',
              build: (format) async => buildReceiptPdf(
                d,
                logo: await loadLogoBytes(ref),
                format: format,
              ),
            ),
          );
        },
      ),
    );
  }
}
