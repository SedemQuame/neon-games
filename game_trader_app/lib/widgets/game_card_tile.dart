import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'price_label.dart';
import 'tag_badge.dart';

class GameCardTile extends StatefulWidget {
  const GameCardTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    this.onTap,
    this.onPlayDemo,
    this.onPlayReal,
    this.tag,
    this.minStake,
    this.highlighted = false,
    this.compact = false,
    this.aspectRatio,
    this.playersCount = 0,
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback? onTap;
  final VoidCallback? onPlayDemo;
  final VoidCallback? onPlayReal;
  final String? tag;
  final num? minStake;
  final bool highlighted;
  final bool compact;
  final double? aspectRatio;
  final int playersCount;

  @override
  State<GameCardTile> createState() => _GameCardTileState();
}

class _GameCardTileState extends State<GameCardTile> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final highlightBorder = widget.highlighted
        ? colors.primary.withValues(alpha: 0.65)
        : colors.border.withValues(alpha: 0.2); // Subtle border
    final cardShadows = context.elevation.card;

    if (widget.compact) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            scale: _pressed ? 0.985 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(context.radii.lg),
                onTap: widget.onTap,
                onHighlightChanged: (value) => setState(() => _pressed = value),
                child: Ink(
                  decoration: BoxDecoration(
                    color: colors.bgCard,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    border: Border.all(color: highlightBorder),
                    boxShadow: cardShadows,
                  ),
                  child: _CompactGameCardContent(widget: widget, isHovered: _hovered),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget imageContent = AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              scale: _pressed ? 0.985 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  onTap: widget.onTap,
                  onHighlightChanged: (value) => setState(() => _pressed = value),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: colors.bgCard,
                      borderRadius: BorderRadius.circular(context.radii.lg),
                      border: Border.all(color: highlightBorder),
                      boxShadow: cardShadows,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(context.radii.lg),
                      child: _GameImageStack(widget: widget, showTag: true, isHovered: _hovered),
                    ),
                  ),
                ),
              ),
            ),
          );

          if (!constraints.hasBoundedHeight) {
            imageContent = AspectRatio(
              aspectRatio: widget.aspectRatio ?? 0.75,
              child: imageContent,
            );
          } else {
            imageContent = Expanded(child: imageContent);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              imageContent,
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.playersCount} playing',
                    style: context.type.label.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompactGameCardContent extends StatelessWidget {
  const _CompactGameCardContent({required this.widget, required this.isHovered});

  final GameCardTile widget;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(context.radii.lg),
          ),
          child: SizedBox(
            width: 104,
            height: double.infinity,
            child: _GameImageStack(widget: widget, showTag: false, isHovered: isHovered),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(context.space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyStrong.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: context.space.xxs),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.label.copyWith(
                    color: colors.textSecondary,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: context.space.sm),
                Wrap(
                  spacing: context.space.xs,
                  runSpacing: context.space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.tag != null)
                      TagBadge(
                        label: widget.tag!,
                        backgroundColor: colors.primary.withValues(alpha: 0.1),
                        foregroundColor: colors.primary,
                      ),
                    if (widget.minStake != null)
                      PriceLabel(value: widget.minStake, label: 'Entry'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GameImageStack extends StatelessWidget {
  const _GameImageStack({
    required this.widget,
    required this.showTag,
    required this.isHovered,
  });

  final GameCardTile widget;
  final bool showTag;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.imagePath, fit: BoxFit.cover),
        
        // Title overlay (gradient at the bottom)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              context.space.md, 
              context.space.xl, 
              context.space.md, 
              context.space.md,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodyStrong.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (widget.minStake != null) ...[
                  const SizedBox(height: 2),
                  PriceLabel(value: widget.minStake),
                ],
              ],
            ),
          ),
        ),

        // Hover dark overlay
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: Colors.black.withValues(alpha: isHovered ? 0.65 : 0.0),
        ),

        // Hover buttons
        if (isHovered)
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.space.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.onPlayDemo != null || widget.onTap != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onPlayDemo ?? widget.onTap,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
                        ),
                        child: const Text('Fun Play', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    if (widget.onPlayReal != null || widget.onTap != null)
                      const SizedBox(width: 8),
                  ],
                  if (widget.onPlayReal != null || widget.onTap != null)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: widget.onPlayReal ?? widget.onTap,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Real Play', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // Top badges
        if (widget.tag != null && showTag)
          Positioned(
            top: context.space.xs,
            left: context.space.xs,
            child: TagBadge(label: widget.tag!),
          ),
      ],
    );
  }
}
