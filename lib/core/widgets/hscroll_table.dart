import 'package:flutter/material.dart';

/// Lets a wide table (a [DataTable]) fill the available width when there is
/// room, and scroll sideways instead of overflowing when there is not.
class HScrollTable extends StatelessWidget {
  final Widget child;
  const HScrollTable({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: child,
        ),
      ),
    );
  }
}
