import 'dart:async';

import 'package:PiliPlus/common/widgets/video_card/video_card_transition.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

double _pageOpacity(WidgetTester tester) =>
    (1 -
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('video-transition-page-veil')),
            )
            .color
            .a) *
    tester
        .widget<FadeTransition>(
          find.byKey(const ValueKey('video-transition-page')),
        )
        .opacity
        .value;

void main() {
  setUp(() {
    _PlaybackProbeController.creations = 0;
    _ContentProbeState.creations = 0;
    _PaintProbe.paints = 0;
  });
  tearDown(Get.reset);
  predictiveBackTests();
  interruptedEntryTests();
  coverFlightTests();
  testWidgets(
    'cover gate waits for frame and dimensions, ignores stale entry',
    (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final gate = VideoFirstFrameGate();
      final first = Completer<void>();
      final firstRect = ValueNotifier<Rect?>(null);
      gate.bind(
        identity: first,
        firstFrame: first.future,
        videoRect: firstRect,
      );
      firstRect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
      await tester.pump();
      expect(gate.ready, isFalse);
      final second = Completer<void>();
      final secondRect = ValueNotifier<Rect?>(Rect.zero);
      gate.bind(
        identity: second,
        firstFrame: second.future,
        videoRect: secondRect,
      );
      first.complete();
      await tester.pump();
      expect(gate.ready, isFalse);
      second.complete();
      await tester.pump();
      expect(gate.ready, isFalse);
      secondRect.value = const Rect.fromLTWH(0, 0, 1, 1);
      await tester.pump();
      expect(gate.ready, isFalse);
      secondRect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
      await tester.pump();
      expect(gate.ready, isFalse);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gate.ready, isTrue);
      gate.dispose();
      firstRect.dispose();
      secondRect.dispose();
    },
  );
  for (final cancel in [false, true]) {
    testWidgets(
      'entry readiness ignores offstage measurement; cancel=$cancel',
      (tester) async {
        await tester.pumpWidget(
          GetMaterialApp(
            navigatorObservers: [routeObserver],
            home: const _SourcePage(preserveChildHeroes: false),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('video-card')));
        await tester.pump();
        bool? ready;
        final pending = waitForVideoPageEntry('video-card-transition-test')
            .then((value) => ready = value);
        await tester.pump(const Duration(milliseconds: 32));
        expect(ready, isNull);
        expect(_pageOpacity(tester), 0);
        expect(_PaintProbe.paints, greaterThan(0));
        if (cancel) Navigator.of(tester.element(find.text('播放页'))).pop();
        await tester.pumpAndSettle();
        await pending;
        expect(ready, !cancel);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(
          await waitForVideoPageEntry('video-card-transition-test'),
          isTrue,
        );
      },
    );
  }
  for (final preserveChildHeroes in [false, true]) {
    testWidgets(
      'return content handoff (nested Heroes: $preserveChildHeroes)',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          GetMaterialApp(
            theme: ThemeData(
              cardColor: const Color(0xffbbaa77),
              canvasColor: const Color(0xff223344),
            ),
            navigatorObservers: [routeObserver],
            home: _SourcePage(preserveChildHeroes: preserveChildHeroes),
          ),
        );
        final card = find.byKey(const ValueKey('video-card'));
        final initial = tester.getRect(card);
        final cardColor = Theme.of(tester.element(card)).cardColor;
        final pageColor = Theme.of(tester.element(card)).canvasColor;
        await tester.tap(card);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final flight = find.byKey(const ValueKey('video-transition-flight'));
        expect(tester.getRect(flight).width, greaterThan(initial.width + 1));
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ImageFiltered), findsNothing);
        expect(find.byType(SnapshotWidget), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(
          find.byKey(const ValueKey('video-transition-dim')),
          findsOneWidget,
        );
        expect(_pageOpacity(tester), 0);
        final firstSurface = tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('video-transition-surface')),
            )
            .color;
        expect(firstSurface, isNot(cardColor));
        expect(firstSurface, isNot(pageColor));
        expect(
          tester
              .widget<ColoredBox>(
                find.byKey(const ValueKey('video-transition-flight-surface')),
              )
              .color,
          firstSurface,
        );
        await tester.pump(
          Duration(
            milliseconds: videoPageTransitionDuration.inMilliseconds ~/ 2,
          ),
        );
        expect(_pageOpacity(tester), greaterThan(0));
        expect(_pageOpacity(tester), 1);
        await tester.pump(videoPageTransitionDuration); // expansion complete
        expect(_pageOpacity(tester), 1);
        expect(
          tester
              .widget<ColoredBox>(
                find.byKey(const ValueKey('video-transition-surface')),
              )
              .color,
          pageColor,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('video-transition-dim')),
          findsNothing,
        );
        expect(Get.routing.route, isA<GetPageRoute>());
        expect(Get.currentRoute, '/videoV');
        expect(Get.arguments['heroTag'], 'video-card-transition-test');
        expect(Get.isRegistered<_PlaybackProbeController>(), isTrue);
        expect(_PlaybackProbeController.creations, 1);
        expect(_ContentProbeState.creations, 1);
        final page = find.byKey(
          const ValueKey('video-transition-page-container'),
        );
        final full = tester.getRect(page);
        Navigator.of(tester.element(find.text('播放页'))).pop();
        await tester.pump();
        var previous = full;
        var previousOpacity = 1.0;
        final reverseStep = Duration(
          milliseconds:
              (videoPageReverseTransitionDuration.inMilliseconds - 24) ~/ 8,
        );
        for (var step = 1; step <= 9; step++) {
          await tester.pump(
            step == 1 ? const Duration(milliseconds: 16) : reverseStep,
          );
          final rect = tester.getRect(page);
          expect(rect.width, lessThan(previous.width));
          expect(rect.height, lessThan(previous.height));
          final opacity = _pageOpacity(tester);
          expect(opacity, lessThan(previousOpacity));
          final contraction =
              (full.width - rect.width) / (full.width - initial.width);
          expect(
            opacity,
            closeTo(1 - Curves.easeOutCubic.transform(contraction), 0.001),
          );
          if (contraction >= 0.5) expect(opacity, lessThan(0.15));
          expect(
            tester
                .widget<ColoredBox>(
                  find.byKey(const ValueKey('video-transition-surface')),
                )
                .color
                .toARGB32(),
            Color.lerp(cardColor, pageColor, 1 - contraction)!.toARGB32(),
          );
          previousOpacity = opacity;
          expect(
            find.byKey(const ValueKey('video-transition-dim')),
            findsNothing,
          );
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(ImageFiltered), findsNothing);
          expect(
            find.byKey(const ValueKey('video-transition-flight')),
            findsNothing,
          );
          final returnCard = find.byKey(
            const ValueKey('video-transition-return-card'),
          );
          final returnRect = tester.getRect(returnCard);
          expect(returnRect.left, closeTo(rect.left, 0.001));
          expect(returnRect.top, closeTo(rect.top, 0.001));
          expect(returnRect.width, closeTo(rect.width, 0.001));
          expect(returnRect.height, closeTo(rect.height, 0.001));
          final cardOpacity = tester
              .widget<Opacity>(
                find.byKey(
                  const ValueKey('video-transition-return-card-opacity'),
                ),
              )
              .opacity;
          expect(cardOpacity + opacity, closeTo(1, 0.001));
          if (contraction >= 0.5) expect(cardOpacity, greaterThan(0.85));
          expect(
            find.descendant(
              of: returnCard,
              matching: find.byKey(const ValueKey('video-card')),
            ),
            findsOneWidget,
          );
          expect(_PlaybackProbeController.creations, 1);
          expect(_ContentProbeState.creations, 1);
          expect(tester.takeException(), isNull);
          previous = rect;
        }
        expect(previous.center.dx, closeTo(initial.center.dx, 1));
        expect(previous.width, closeTo(initial.width, 5));
        await tester.pumpAndSettle();
        expect(card, findsOneWidget);
        expect(Get.isRegistered<_PlaybackProbeController>(), isFalse);
      },
    );
  }
  testWidgets('content preparation starts before the entry settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        navigatorObservers: [routeObserver],
        home: const _SourcePage(preserveChildHeroes: false),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('video-card')));
    await tester.pump();
    bool? ready;
    final pending = waitForVideoPageEntry('video-card-transition-test').then(
      (value) => ready = value,
    );
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();
    final route = Get.routing.route as VideoPageTransitionRoute<void>;
    expect(ready, isTrue);
    expect(route.animation!.value, lessThan(1));
    await tester.pumpAndSettle();
    await pending;
  });
  testWidgets('page UI is visible around the middle of card expansion', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        navigatorObservers: [routeObserver],
        home: const _SourcePage(preserveChildHeroes: false),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('video-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 410));
    final route = Get.routing.route as VideoPageTransitionRoute<void>;
    expect(_pageOpacity(tester), 1);
    expect(route.animation!.value, lessThan(1));
    await tester.pumpAndSettle();
  });
}

void coverFlightTests() {
  testWidgets('cover uses its painted card rect and the player rect', (
    tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: _CoverSourcePage()));
    final source = tester.getRect(find.byKey(const ValueKey('source-cover')));
    final card = tester.getRect(find.byKey(const ValueKey('cover-card')));
    expect(source, isNot(card));
    await tester.tap(find.byKey(const ValueKey('cover-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final flight = find.byKey(const ValueKey('video-cover-flight'));
    expect(flight, findsOneWidget);
    final early = tester.getRect(flight);
    expect(early.left, closeTo(source.left, 8));
    expect(early.top, closeTo(source.top, 8));
    expect(
      find.descendant(
        of: flight,
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.orange,
        ),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 320));
    final middle = tester.getRect(flight);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('video-cover-flight-opacity')),
          )
          .opacity,
      0,
    );
    expect(middle.width, greaterThan(early.width));
    expect(middle.left, lessThan(early.left));
    await tester.pumpAndSettle();
    final player = tester.getRect(find.byKey(const ValueKey('player-cover')));
    expect(player, const Rect.fromLTWH(32, 80, 320, 180));
    expect(flight, findsNothing);
    final route = Get.routing.route as VideoPageTransitionRoute<void>;
    // ignore: cascade_invocations
    route
      ..handleStartBackGesture(progress: 1)
      ..handleUpdateBackGestureProgress(progress: 0.5);
    await tester.pump();
    expect(flight, findsOneWidget);
    route.handleCancelBackGesture();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('player-cover'))), player);
    route
      ..handleStartBackGesture(progress: 1)
      ..handleUpdateBackGestureProgress(progress: 0.5);
    await tester.pump();
    route.handleCommitBackGesture();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-cover')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cover-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-cover')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover flight reverses during unfinished entry', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: _CoverSourcePage()));
    await tester.tap(find.byKey(const ValueKey('cover-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final flight = find.byKey(const ValueKey('video-cover-flight'));
    final enlarged = tester.getRect(flight);
    Navigator.of(tester.element(find.byType(_CoverTargetPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(flight).width, lessThan(enlarged.width));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-cover')), findsOneWidget);
    expect(flight, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late content follows player and introduction', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: _CoverSourcePage()));
    await tester.tap(find.byKey(const ValueKey('cover-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final late = tester.widget<Opacity>(
      find.byKey(const ValueKey('video-transition-late-content')),
    );
    expect(_pageOpacity(tester), 1);
    expect(late.opacity, lessThan(0.5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('video-transition-late-content')),
          )
          .opacity,
      greaterThan(late.opacity),
    );
    await tester.pumpAndSettle();
  });
}

class _CoverSourcePage extends StatelessWidget {
  const _CoverSourcePage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: GestureDetector(
        key: const ValueKey('cover-card'),
        onTap: () => Navigator.of(context).push(
          VideoPageTransitionRoute<void>(
            settings: const RouteSettings(
              name: '/videoV',
              arguments: {'heroTag': 'cover-geometry'},
            ),
            builder: (_) => const _CoverTargetPage(),
          ),
        ),
        child: VideoCardHero(
          tag: 'cover-geometry',
          surfaceColor: Theme.of(context).cardColor,
          preserveChildHeroes: true,
          surfaceOnlyFlight: true,
          child: const SizedBox(
            width: 200,
            height: 140,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.grey)),
                Positioned(
                  left: 15,
                  top: 22,
                  width: 120,
                  height: 70,
                  child: VideoCoverHero(
                    tag: 'cover-geometry',
                    child: ColoredBox(
                      key: ValueKey('source-cover'),
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CoverTargetPage extends StatelessWidget {
  const _CoverTargetPage();

  @override
  Widget build(BuildContext context) => VideoPageHeroTarget(
    tag: 'cover-geometry',
    surfaceColor: Theme.of(context).canvasColor,
    child: const Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 32,
            top: 80,
            width: 320,
            height: 180,
            child: VideoCoverHero(
              tag: 'cover-geometry',
              child: ColoredBox(
                key: ValueKey('player-cover'),
                color: Colors.blue,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 280,
            child: Text('视频简介'),
          ),
          Positioned(
            left: 16,
            top: 340,
            child: VideoTransitionLayer(
              child: Text('评论和推荐'),
            ),
          ),
        ],
      ),
    ),
  );
}

void interruptedEntryTests() {
  for (final delay in [
    16,
    120,
    280,
    videoPageTransitionDuration.inMilliseconds - 80,
  ]) {
    for (final nested in [false, true]) {
      testWidgets('return during entry at ${delay}ms (nested: $nested)', (
        tester,
      ) async {
        await tester.pumpWidget(
          GetMaterialApp(
            navigatorObservers: [routeObserver],
            home: _SourcePage(preserveChildHeroes: nested),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('video-card')));
        await tester.pump();
        await tester.pump(Duration(milliseconds: delay));
        final route = Get.routing.route as VideoPageTransitionRoute<void>;
        final flight = find.byKey(const ValueKey('video-transition-flight'));
        final page = find.byKey(
          const ValueKey('video-transition-page-container'),
        );
        var previous = tester.getRect(flight);
        var previousOpacity = _pageOpacity(tester);
        route.navigator!.pop();
        await tester.pump();
        while (flight.evaluate().isNotEmpty) {
          final rect = tester.getRect(flight);
          expect(rect.width, lessThanOrEqualTo(previous.width + 0.001));
          expect(rect.height, lessThanOrEqualTo(previous.height + 0.001));
          final clip = tester
              .widget<ClipRRect>(page)
              .clipper!
              .getClip(tester.getSize(page))
              .outerRect
              .shift(tester.getTopLeft(page));
          expect(clip.left, closeTo(rect.left, 0.001));
          expect(clip.top, closeTo(rect.top, 0.001));
          expect(clip.width, closeTo(rect.width, 0.001));
          expect(clip.height, closeTo(rect.height, 0.001));
          expect(_pageOpacity(tester), lessThanOrEqualTo(previousOpacity));
          expect(
            find.byKey(const ValueKey('video-transition-return-card')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('video-transition-dim')),
            findsNothing,
          );
          previous = rect;
          previousOpacity = _pageOpacity(tester);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(Get.isRegistered<_PlaybackProbeController>(), isFalse);
        expect(find.byKey(const ValueKey('video-card')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void predictiveBackTests() {
  for (final cancel in [false, true]) {
    testWidgets('predictive back continues once (cancel: $cancel)', (
      tester,
    ) async {
      await tester.pumpWidget(
        GetMaterialApp(
          navigatorObservers: [routeObserver],
          home: const _SourcePage(preserveChildHeroes: false),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('video-card')));
      await tester.pumpAndSettle();
      final route = Get.routing.route as VideoPageTransitionRoute<void>;
      final owner = route.navigator!;
      final page = find.byKey(
        const ValueKey('video-transition-page-container'),
      );
      final full = tester.getRect(page);
      route
        ..handleStartBackGesture(progress: 1)
        ..handleUpdateBackGestureProgress(progress: 0.55);
      await tester.pump();
      final dragged = tester.getRect(page);
      expect(dragged.width, lessThan(full.width));
      expect(find.byKey(const ValueKey('video-transition-dim')), findsNothing);
      if (cancel) {
        route.handleCancelBackGesture();
        await tester.pumpAndSettle();
        expect(route.isCurrent, isTrue);
        expect(owner.userGestureInProgress, isFalse);
        expect(tester.getRect(page), full);
        expect(_pageOpacity(tester), 1);
        // Cancelling must not prevent a later, successful gesture.
        route
          ..handleStartBackGesture(progress: 1)
          ..handleUpdateBackGestureProgress(progress: 0.55);
        await tester.pump();
      }
      route.handleCommitBackGesture();
      expect(route.animation!.value, closeTo(0.55, 0.001));
      route.handleCommitBackGesture(); // repeated platform callback is ignored
      await tester.pump();
      var previousWidth = dragged.width;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        final width = tester.getRect(page).width;
        expect(width, lessThanOrEqualTo(previousWidth));
        previousWidth = width;
      }
      await tester.pumpAndSettle();
      expect(owner.userGestureInProgress, isFalse);
      expect(find.byKey(const ValueKey('video-card')), findsOneWidget);
      expect(Get.isRegistered<_PlaybackProbeController>(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

class _SourcePage extends StatelessWidget {
  const _SourcePage({required this.preserveChildHeroes});
  final bool preserveChildHeroes;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: VideoCardHero(
        tag: 'video-card-transition-test',
        surfaceColor: Theme.of(context).cardColor,
        preserveChildHeroes: preserveChildHeroes,
        child: InkWell(
          key: const ValueKey('video-card'),
          onTap: () => Navigator.of(context).push(
            VideoPageTransitionRoute<void>(
              settings: const RouteSettings(
                name: '/videoV',
                arguments: {'heroTag': 'video-card-transition-test'},
              ),
              builder: (_) => const _TargetPage(),
            ),
          ),
          child: SizedBox(
            width: 180,
            height: 120,
            child: preserveChildHeroes
                ? const Hero(
                    tag: 'nested-image',
                    child: ColoredBox(color: Colors.blue),
                  )
                : const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}

class _TargetPage extends StatefulWidget {
  const _TargetPage();
  @override
  State<_TargetPage> createState() => _TargetPageState();
}

class _TargetPageState extends State<_TargetPage>
    with RouteAware, RouteAwareMixin {
  @override
  void initState() {
    super.initState();
    Get.put(_PlaybackProbeController());
  }

  @override
  Widget build(BuildContext context) => VideoPageHeroTarget(
    tag: 'video-card-transition-test',
    surfaceColor: Theme.of(context).canvasColor,
    child: const _ContentProbe(),
  );
}

class _PlaybackProbeController extends GetxController {
  _PlaybackProbeController() {
    creations++;
  }
  static int creations = 0;
}

class _ContentProbe extends StatefulWidget {
  const _ContentProbe();

  @override
  State<_ContentProbe> createState() => _ContentProbeState();
}

class _ContentProbeState extends State<_ContentProbe> {
  static int creations = 0;

  @override
  void initState() {
    super.initState();
    creations++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomPaint(
      painter: _PaintProbe(),
      child: const Center(child: Text('播放页')),
    ),
  );
}

class _PaintProbe extends CustomPainter {
  static int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
  }

  @override
  bool shouldRepaint(_PaintProbe oldDelegate) => false;
}
