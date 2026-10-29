import 'package:PiliPlus/plugin/pl_player/widgets/video_frame_gate.dart';
import 'package:PiliPlus/utils/video_frame_experiment.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

int textureLayers(Layer root) {
  var count = root is TextureLayer ? 1 : 0;
  if (root is ContainerLayer) {
    for (
      var child = root.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      count += textureLayers(child);
    }
  }
  return count;
}

void main() {
  for (final livePaint in [videoFrameExperimentLivePaint, false]) {
    testWidgets('waiting gate: livePaint=$livePaint', (tester) async {
      final boundary = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 160,
                height: 90,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VideoFrameGate(
                        ready: false,
                        livePaint: livePaint,
                        fill: const Color(0xff336699),
                        owner: boundary,
                        child: const Texture(textureId: 42),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      expect(textureLayers(render.debugLayer!), livePaint ? 1 : 0);
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);
      // The fake texture validates the production gate's layer contract only.
      // It cannot establish Android GPU consumption or new-source ownership.
    });
  }
  testWidgets('ready media is painted with both strategies', (tester) async {
    for (final livePaint in [false, true]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 160,
            height: 90,
            child: VideoFrameGate(
              ready: true,
              livePaint: livePaint,
              fill: const Color(0xff336699),
              owner: boundary,
              child: const Texture(textureId: 42),
            ),
          ),
        ),
      );
      expect(
        textureLayers(
          (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
              .debugLayer!,
        ),
        1,
      );
      expect(find.byType(ColoredBox), findsNothing);
    }
  });
}
