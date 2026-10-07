import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Confirmation dialog for a cancellation (payment or registration): always
/// requires a reason, since "annuler, en cas d'erreur" must stay auditable —
/// never a silent deletion. Returns the trimmed reason, or null if aborted.
Future<String?> showCancelReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final reason = controller.text.trim();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: "Motif de l'annulation (obligatoire)",
                    helperText:
                        "Ex. : erreur de saisie, doublon... Ce motif restera visible dans l'historique.",
                    helperMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Retour'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              onPressed: reason.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, reason),
              child: const Text("Confirmer l'annulation"),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}

/// Small colored status badge, e.g. "ANNULÉ" (default, red) or "PROVISOIRE"
/// (gold) — shown wherever a flagged record appears.
class CancelledBadge extends StatelessWidget {
  final String label;
  final Color color;
  const CancelledBadge({
    super.key,
    this.label = 'ANNULÉ',
    this.color = AppColors.danger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
