import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Standard page layout: title (+ subtitle) and actions on top, content below.
/// Margins shrink and the actions drop under the title on narrow windows.
class PageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final gutter = narrow ? 16.0 : 32.0;

        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: narrow
                  ? Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)
                  : Theme.of(context).textTheme.headlineSmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ],
        );
        final actionBar = Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: actions,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                narrow ? 16 : 28,
                gutter,
                16,
              ),
              child: narrow || actions.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          actionBar,
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 16),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.5,
                          ),
                          child: actionBar,
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
