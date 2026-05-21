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
    required this.onTap,
    this.tag,
    this.minStake,
    this.highlighted = false,
    this.compact = false,
    this.aspectRatio,
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback onTap;
  final String? tag;
  final num? minStake;
  final bool highlighted;
  final bool compact;
  final double? aspectRatio;

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
        : colors.border;
    final cardShadows = context.elevation.card;

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
                child: widget.compact
                    ? _CompactGameCardContent(widget: widget, isHovered: _hovered)
                    : _StackedGameCardContent(widget: widget, isHovered: _hovered),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StackedGameCardContent extends StatelessWidget {
  const _StackedGameCardContent({required this.widget, required this.isHovered});

  final GameCardTile widget;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.radii.lg),
          ),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio ?? (3 / 4),
            child: _GameImageStack(widget: widget, showTag: true, isHovered: isHovered),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(context.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodyStrong.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.label.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '10k+',
                    style: context.type.label.copyWith(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              if (widget.minStake != null) ...[
                SizedBox(height: context.space.sm),
                PriceLabel(value: widget.minStake),
              ],
            ],
          ),
        ),
      ],
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
    final colors = context.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.imagePath, fit: BoxFit.cover),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: Colors.black.withValues(alpha: isHovered ? 0.4 : 0.0),
        ),
        if (isHovered)
          Center(
             child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor,
                ),
                child: const Icon(Icons.play_arrow, color: AppTheme.goldText),
             ),
           ),
        if (widget.highlighted && showTag)
          Positioned(
            right: context.space.xs,
            bottom: context.space.xs,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.space.xs,
                vertical: context.space.xxs,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(context.radii.pill),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'ROOM PLAY',
                style: context.type.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
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
