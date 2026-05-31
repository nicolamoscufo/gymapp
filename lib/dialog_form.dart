import 'dart:math' as math;

import 'package:flutter/material.dart';

const appDialogFieldGap = SizedBox(height: 12);

double _dialogWidth(BuildContext context, double maxWidth) {
  final availableWidth = math.max(0.0, MediaQuery.sizeOf(context).width - 96);
  return math.min(maxWidth, availableWidth);
}

class AppDialogFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AppDialogFrame({super.key, required this.child, this.maxWidth = 520});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: _dialogWidth(context, maxWidth), child: child);
  }
}

class AppDialogContent extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final CrossAxisAlignment crossAxisAlignment;

  const AppDialogContent({
    super.key,
    required this.children,
    this.maxWidth = 520,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      maxWidth: maxWidth,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        ),
      ),
    );
  }
}

class AppFieldRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double minFieldWidth;

  const AppFieldRow({
    super.key,
    required this.children,
    this.spacing = 12,
    this.minFieldWidth = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minRowWidth =
            children.length * minFieldWidth + (children.length - 1) * spacing;
        final stackFields = constraints.maxWidth < minRowWidth;

        if (stackFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) SizedBox(height: spacing),
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(width: spacing),
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}
