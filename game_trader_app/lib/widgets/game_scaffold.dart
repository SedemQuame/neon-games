import 'package:flutter/material.dart';

import '../app_theme.dart';

class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.backgroundColor = AppTheme.gameBackground,
    this.maxWidth = 550,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Color backgroundColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    // 60% on desktop, 90% on mobile/tablet
    final effectiveMaxWidth = isDesktop ? screenWidth * 0.6 : screenWidth * 0.9;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar != null 
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
                  child: bottomNavigationBar,
                ),
              ],
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
          child: body,
        ),
      ),
    );
  }
}
