import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/video_card/video_card_transition.dart';
import 'package:material_ui/material_ui.dart';

/// Shared geometry for loading and resolved headers. Known title data never
/// moves merely because the owner/metadata request has completed.
class UgcIntroHeader extends StatelessWidget {
  const UgcIntroHeader({super.key, required this.owner, required this.title});
  final Widget owner;
  final Widget title;

  static double ownerExtent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return max(40, 1.5 * (scaler.scale(13) + scaler.scale(12)));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      UgcIntroOwnerSlot(child: owner),
      const SizedBox(height: 8),
      UgcIntroTitleSlot(child: title),
    ],
  );
}

class UgcIntroOwnerSlot extends StatelessWidget {
  const UgcIntroOwnerSlot({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => VideoTransitionTargetPart(
    part: VideoTransitionPart.owner,
    child: SizedBox(height: UgcIntroHeader.ownerExtent(context), child: child),
  );
}

class UgcIntroTitleSlot extends StatelessWidget {
  const UgcIntroTitleSlot({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => VideoTransitionTargetPart(
    part: VideoTransitionPart.title,
    child: child,
  );
}

/// Data readiness is independent of route progress. Only the introduction
/// crossfades; the page and live player above it are never replaced or faded.
class UgcIntroContent extends StatelessWidget {
  const UgcIntroContent({
    super.key,
    required this.loading,
    required this.title,
    this.child,
  }) : assert(loading || child != null);

  final bool loading;
  final String? title;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [
          for (final child in previous)
            Positioned.fill(
              child: Offstage(
                child: ExcludeSemantics(child: IgnorePointer(child: child)),
              ),
            ),
          ?current,
        ],
      ),
      child: loading
          ? UgcIntroLoadingSkeleton(
              key: const ValueKey('loading'),
              title: title,
            )
          : KeyedSubtree(key: const ValueKey('resolved'), child: child!),
    ),
  );
}

/// A static, inexpensive placeholder; it never invents video metadata.
class UgcIntroLoadingSkeleton extends StatelessWidget {
  const UgcIntroLoadingSkeleton({super.key, required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, {double height = 10}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return Column(
      key: const ValueKey('ugc-intro-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UgcIntroHeader(
          owner: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(100),
                    const SizedBox(height: 6),
                    bar(68, height: 8),
                  ],
                ),
              ),
              bar(52, height: 24),
            ],
          ),
          title: title != null && title!.isNotEmpty
              ? Text(
                  title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(double.infinity, height: 14),
                    const SizedBox(height: 6),
                    bar(160, height: 14),
                  ],
                ),
        ),
        VideoTransitionTargetPart(
          part: VideoTransitionPart.details,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              bar(180, height: 8),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (_) => bar(36, height: 28)),
              ),
              const SizedBox(height: 18),
              bar(double.infinity, height: 48),
            ],
          ),
        ),
      ],
    );
  }
}
