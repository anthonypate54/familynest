import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              isDarkMode
                  ? [
                    // Dark mode: explicitly use AppTheme dark colors
                    AppTheme.darkBackgroundColor,
                    AppTheme.darkSurfaceColor,
                  ]
                  : [
                    // Light mode: original bright gradient
                    AppTheme.primaryColor,
                    AppTheme.secondaryColor,
                  ],
        ),
      ),
      child: child,
    );
  }
}
