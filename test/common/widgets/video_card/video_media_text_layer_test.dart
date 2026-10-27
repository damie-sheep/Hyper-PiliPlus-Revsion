import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/video_card/video_card_transition.dart';
import 'package:PiliPlus/common/widgets/video_card/video_media_text_layer.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final type in DanmakuItemType.values) {
    testWidgets(
      'real $type text clips to media, exits and restores on cancel',
      (tester) async {
        tester.view.physicalSize = const Size(400, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nav = GlobalKey<NavigatorState>();
        final boundary = GlobalKey();
        final owns = ValueNotifier(true);
        addTearDown(owns.dispose);
        DanmakuController<void>? controller;
        var active = false;
        var taps = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(),
            ),
          ),
        );
        final route = _TextRoute(
          builder: (_) => Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xff222222)),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  width: 400,
                  height: 160,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: owns,
                    builder: (_, owns, _) => VideoMediaTextLayer(
                      ownsSource: owns,
                      child: Builder(
                        builder: (context) {
                          active = VideoMediaTextScope.activeOf(context);
                          if (active) {
                            controller?.resume();
                          } else {
                            controller?.pause();
                          }
                          return DanmakuScreen<void>(
                            size: const Size(400, 160),
                            option: const DanmakuOption(
                              fontSize: 24,
                              strokeWidth: 0,
                            ),
                            createdController: (value) {
                              controller = value;
                              if (!active) value.pause();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 300,
                  top: 200,
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('CONTROL'),
                  ),
                ),
              ],
            ),
          ),
        );
        nav.currentState!.push(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(active, isFalse);
        await tester.pumpAndSettle();
        expect(active, isTrue);
        void addText() {
          if (type == DanmakuItemType.special) {
            for (final y in [0.2, 1.2]) {
              controller!.addDanmaku(
                SpecialDanmakuContentItem<void>(
                  'MMMM',
                  duration: 10000,
                  color: const Color(0xffffff00),
                  fontSize: 24,
                  translateXTween: ConstantTween(0.1),
                  translateYTween: ConstantTween(y),
                ),
              );
            }
          } else {
            controller!.addDanmaku(
              DanmakuContentItem<void>(
                'MMMM',
                type: type,
                color: const Color(0xffffff00),
              ),
            );
          }
        }

        Future<(int, int)> pixels() async => (await tester.runAsync(() async {
          final box = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundary),
          );
          final image = await box.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var inside = 0;
          var outside = 0;
          for (var y = 0; y < 380; y++) {
            for (var x = 0; x < 400; x++) {
              final i = (y * image.width + x) * 4;
              if (bytes[i] > 200 && bytes[i + 1] > 200 && bytes[i + 2] < 60) {
                if (y < 160) {
                  inside++;
                } else {
                  outside++;
                }
              }
            }
          }
          image.dispose();
          return (inside, outside);
        }))!;
        addText();
        await tester.pump(const Duration(milliseconds: 32));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
        expect((await pixels()).$1, greaterThan(0));
        expect((await pixels()).$2, 0);
        route
          ..handleStartBackGesture(progress: 1)
          ..handleUpdateBackGestureProgress(progress: 0.4);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(active, isFalse);
        expect(await pixels(), (0, 0));
        route.handleCancelBackGesture();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 64));
        expect(active, isTrue);
        expect((await pixels()).$1, greaterThan(0));
        owns.value = false;
        await tester.pump();
        expect(active, isFalse);
        expect(await pixels(), (0, 0));
        // Late old-source text remains hidden; controls are outside this layer.
        addText();
        await tester.pump(const Duration(milliseconds: 64));
        expect(await pixels(), (0, 0));
        await tester.tap(find.text('CONTROL'));
        expect(taps, 1);
        owns.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 64));
        expect(active, isTrue);
        expect((await pixels()).$1, greaterThan(0));
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(await pixels(), (0, 0));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TextRoute extends VideoPageTransitionRoute<void> {
  _TextRoute({required super.builder});
}
