import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/db_providers.dart';
import '../theme/app_theme.dart';
import 'school_logo.dart';

/// Full-screen "connecting to the server" view shown at startup.
class ConnectingView extends ConsumerWidget {
  const ConnectingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dbStatusProvider);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SchoolLogo(size: 120),
              const SizedBox(height: 24),
              ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, text, _) => Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(minHeight: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen error when the server cannot be reached.
class ConnectionErrorView extends ConsumerWidget {
  final Object error;
  const ConnectionErrorView({super.key, required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connexion impossible',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Le serveur de l'école ne répond pas. Vérifiez que le poste serveur "
                      'est allumé et que ce poste est bien sur le même réseau, puis réessayez.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text(
                        'Détails techniques',
                        style: TextStyle(fontSize: 13),
                      ),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        SelectableText(
                          '$error',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(dbReadyProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
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
