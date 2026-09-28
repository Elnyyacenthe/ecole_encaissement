import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/data_providers.dart';
import '../theme/app_theme.dart';

/// Accepted file names for a bundled logo, tried in order when no logo has
/// been saved in the database.
const List<String> kLogoAssets = [
  'assets/images/logo.png',
  'assets/images/logo.jpg',
  'assets/images/logo.jpeg',
];

/// School logo: the one chosen in Paramètres (stored in the database), else a
/// bundled file, else a "MP" monogram.
class SchoolLogo extends ConsumerWidget {
  final double size;
  const SchoolLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(logoBytesProvider).value;
    if (saved != null) {
      return Image.memory(
        saved,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _try(0),
      );
    }
    return _try(0);
  }

  Widget _try(int index) {
    if (index >= kLogoAssets.length) return _monogram();
    return Image.asset(
      kLogoAssets[index],
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _try(index + 1),
    );
  }

  Widget _monogram() => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [AppColors.navy, AppColors.navyDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Text(
      'MP',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.36,
      ),
    ),
  );
}
