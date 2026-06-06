import 'package:flutter/material.dart';

import '../app_theme.dart';

class CasinoScaffold extends StatelessWidget {
  const CasinoScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.maxContentWidth = 1240,
    this.bodyPadding,
    this.constrainBody = true,
    this.resizeToAvoidBottomInset,
    this.useNarrowLayout = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double maxContentWidth;
  final EdgeInsetsGeometry? bodyPadding;
  final bool constrainBody;
  final bool? resizeToAvoidBottomInset;
  final bool useNarrowLayout;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: context.colors.bgApp,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                useNarrowLayout 
                    ? SizedBox(
                        width: isDesktop ? screenWidth * 0.6 : screenWidth * 0.9,
                        child: bottomNavigationBar,
                      )
                    : Expanded(child: bottomNavigationBar!),
              ],
            )
          : null,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppTheme.backgroundDark),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = _responsiveHorizontalPadding(constraints.maxWidth);
            
            double contentWidth;
            if (useNarrowLayout) {
              contentWidth = isDesktop ? screenWidth * 0.6 : screenWidth * 0.9;
            } else {
              contentWidth = constraints.maxWidth > maxContentWidth
                  ? maxContentWidth
                  : constraints.maxWidth;
            }

            final content = Padding(
              padding: bodyPadding ?? EdgeInsets.symmetric(horizontal: useNarrowLayout ? AppTheme.spacing.md : horizontal),
              child: body,
            );

            return !constrainBody
                ? content
                : Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: contentWidth, child: content),
                  );
          },
        ),
      ),
    );
  }

  double _responsiveHorizontalPadding(double width) {
    if (width >= 1200) {
      return AppTheme.spacing.xxl;
    }
    if (width >= 900) {
      return AppTheme.spacing.xl;
    }
    if (width >= 600) {
      return AppTheme.spacing.lg;
    }
    return AppTheme.spacing.md;
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? EdgeInsets.all(context.space.md),
      decoration: BoxDecoration(
        color: backgroundColor ?? context.colors.bgCard,
        borderRadius: BorderRadius.circular(radius ?? context.radii.lg),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.8)),
      ),
      child: child,
    );
  }
}
