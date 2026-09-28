import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/db_providers.dart';

/// Standard loading / error / data rendering for an [AsyncValue].
class AsyncValueView<T> extends ConsumerWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;

  const AsyncValueView({super.key, required this.value, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      // A background refresh (another PC changed data) keeps showing the
      // current data instead of flashing a spinner.
      skipLoadingOnReload: true,
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error),
    );
  }
}

class ErrorView extends ConsumerWidget {
  final Object error;
  const ErrorView({super.key, required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            SelectableText('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.invalidate(dbReadyProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
