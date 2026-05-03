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
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback onTap;
  final String? tag;
  final num? minStake;
  final bool highlighted;
  final bool compact;

  @override
  State<GameCardTile> createState() => _GameCardTileState();
}

class _GameCardTileState extends State<GameCardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final highlightBorder = widget.highlighted
        ? colors.primary.withValues(alpha: 0.65)
        : colors.border;
    final cardShadows = context.elevation.card;

    return AnimatedScale(
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
                ? _CompactGameCardContent(widget: widget)
                : _StackedGameCardContent(widget: widget),
          ),
        ),
      ),
    );
  }
}

class _StackedGameCardContent extends StatelessWidget {
  const _StackedGameCardContent({required this.widget});

  final GameCardTile widget;

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
            aspectRatio: 16 / 9,
            child: _GameImageStack(widget: widget, showTag: true),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(context.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                style: context.type.body.copyWith(color: colors.textSecondary),
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
  const _CompactGameCardContent({required this.widget});

  final GameCardTile widget;

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
            child: _GameImageStack(widget: widget, showTag: false),
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
  const _GameImageStack({required this.widget, required this.showTag});

  final GameCardTile widget;
  final bool showTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.imagePath, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: widget.highlighted ? 0.56 : 0.4),
                Colors.transparent,
              ],
            ),
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
