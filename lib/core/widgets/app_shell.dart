import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/change_password_form.dart';
import '../../models/app_user.dart';
import '../../repositories/users_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import 'school_logo.dart';

class _Dest {
  final String path;
  final String label;
  final IconData icon;
  const _Dest(this.path, this.label, this.icon);
}

const _gestion = [
  _Dest('/dashboard', 'Tableau de bord', Icons.dashboard_outlined),
  _Dest('/students', 'Élèves', Icons.people_alt_outlined),
  _Dest('/payments', 'Encaissement', Icons.point_of_sale),
  _Dest('/history', 'Historique', Icons.history),
  _Dest('/reports/unpaid', 'Impayés', Icons.assignment_late_outlined),
];

/// Reserved to administrators.
const _configuration = [
  _Dest('/tariffs', 'Tarifs', Icons.sell_outlined),
  _Dest('/settings/school-years', 'Paramètres', Icons.settings_outlined),
];

bool _isAdminOnlyPath(String location) =>
    location.startsWith('/tariffs') || location.startsWith('/settings');

/// Below this window width the menu shrinks to an icon-only rail.
const double kCompactWidth = 1100;

/// The application frame. Only built once the server is reachable and a user
/// is logged in (see AuthGate).
class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const AppShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataSyncProvider);
    final user = ref.watch(authProvider);
    final isAdmin = user?.isAdmin ?? false;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Row(
        // The menu must span the full window height (it scrolls if it is taller).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            location: location,
            compact: size.width < kCompactWidth,
            short: size.height < 760,
            user: user,
          ),
          Expanded(
            child: _isAdminOnlyPath(location) && !isAdmin
                ? const _AccessDenied()
                : child,
          ),
        ],
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Accès réservé aux administrateurs',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              "Votre compte n'a pas le droit d'ouvrir cette page.",
              style: TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Retour au tableau de bord'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String location;

  /// Icon-only rail (narrow windows).
  final bool compact;

  /// Smaller logo and no tagline (low windows).
  final bool short;
  final AppUser? user;
  const _Sidebar({
    required this.location,
    required this.compact,
    required this.short,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 44.0 : (short ? 64.0 : 100.0);
    final ring = logoSize + (compact ? 8 : 12);
    final isAdmin = user?.isAdmin ?? false;

    return Container(
      width: compact ? 76 : 268,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy, AppColors.navyDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: compact || short ? 16 : 28),
                  Center(
                    child: Container(
                      width: ring,
                      height: ring,
                      padding: EdgeInsets.all(compact ? 3 : 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(child: SchoolLogo(size: logoSize)),
                    ),
                  ),
                  if (!compact) ...[
                    SizedBox(height: short ? 8 : 14),
                    const Text(
                      'COSBIMP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    if (!short) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Gestion de scolarité',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: compact || short ? 16 : 24),
                  if (compact)
                    const _RailDivider()
                  else
                    const _SectionLabel('GESTION'),
                  for (final d in _gestion)
                    _NavItem(
                      dest: d,
                      selected: location.startsWith(d.path),
                      compact: compact,
                    ),
                  if (isAdmin) ...[
                    SizedBox(height: compact ? 4 : 12),
                    if (compact)
                      const _RailDivider()
                    else
                      const _SectionLabel('CONFIGURATION'),
                    for (final d in _configuration)
                      _NavItem(
                        dest: d,
                        selected: location.startsWith(d.path),
                        compact: compact,
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (user != null) _UserBadge(user: user!, compact: compact),
        ],
      ),
    );
  }
}

/// Who is logged in, with "change my password" and "log out".
class _UserBadge extends ConsumerWidget {
  final AppUser user;
  final bool compact;
  const _UserBadge({required this.user, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.gold,
      child: Text(
        user.initials,
        style: const TextStyle(
          color: AppColors.navyDark,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 8),
      child: PopupMenuButton<String>(
        tooltip: '${user.fullName} (${user.role.label})',
        position: PopupMenuPosition.over,
        onSelected: (value) async {
          if (value == 'name') {
            final name = await showEditNameDialog(
              context,
              initialName: user.fullName,
            );
            if (name == null || !context.mounted) return;
            try {
              await ref.read(authProvider.notifier).updateOwnName(name);
            } on AuthException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          } else if (value == 'password') {
            showChangePasswordDialog(context);
          } else if (value == 'logout') {
            ref.read(authProvider.notifier).logout();
            context.go('/dashboard');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'name',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.badge_outlined),
              title: Text('Modifier mon nom'),
            ),
          ),
          PopupMenuItem(
            value: 'password',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.key_outlined),
              title: Text('Changer mon mot de passe'),
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.logout),
              title: Text('Se déconnecter'),
            ),
          ),
        ],
        child: compact
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(child: avatar),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            user.role.label,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.more_vert,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Divider(height: 1, color: Colors.white24),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final _Dest dest;
  final bool selected;
  final bool compact;
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      dest.icon,
      size: 20,
      color: selected ? AppColors.gold : Colors.white70,
    );

    final item = Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () => context.go(dest.path),
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: selected ? AppColors.gold : Colors.transparent,
                  width: 3.5,
                ),
              ),
            ),
            child: compact
                ? Center(child: icon)
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          dest.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: dest.label, child: item) : item;
  }
}
