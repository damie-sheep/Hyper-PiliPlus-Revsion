import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_transition.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/common/widgets/video_card/video_transition_geometry.dart';
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/loading_skeleton.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _screenKey = ValueKey('screen');
const _tag = 'transition-probe';
const _playerKey = ValueKey('player');
const _sourceTitleKey = ValueKey('source-title');
const _playerColor = Color(0xff1266dd);
const _readyColor = Color(0xff008844);
const _sourceInk = Color(0xffff00ff);
late _SeekableRoute _route;
int _pageCreations = 0;
int _controllerCreations = 0;
int _playerTaps = 0;
final _samplingCalls = <bool>[];

double _timeFor(double expansion) {
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 40; i++) {
    final mid = (low + high) / 2;
    if (Curves.easeInOutCubic.transform(mid) < expansion) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

Future<void> _seek(WidgetTester tester, double expansion) async {
  _route.seek(_timeFor(expansion));
  await tester.pump();
  await tester.pump();
}

class _Pixels {
  _Pixels(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
  Color at(Offset point) {
    final x = point.dx.floor().clamp(0, width - 1);
    final y = point.dy.floor().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  Rect? magentaBounds() {
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (bytes[i] > bytes[i + 1] + 35 && bytes[i + 2] > bytes[i + 1] + 35) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return right < 0
        ? null
        : Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1);
  }
}

Future<_Pixels> _pixels(WidgetTester tester, [String? name]) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_screenKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    const directory = String.fromEnvironment('VIDEO_TRANSITION_EVIDENCE');
    if (directory.isNotEmpty && name != null) {
      final path = Directory(directory)..createSync(recursive: true);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File('${path.path}/$name.png').writeAsBytesSync(png.buffer.asUint8List());
    }
    final result = _Pixels(
      bytes.buffer.asUint8List(),
      image.width,
      image.height,
    );
    image.dispose();
    return result;
  }))!;
}

Future<Rect> _open(
  WidgetTester tester, {
  bool right = false,
  bool nested = false,
  ValueNotifier<bool>? loaded,
  ValueNotifier<Color>? player,
  ValueNotifier<bool>? sourceVisible,
  ValueNotifier<double>? sourceTop,
  double textScale = 1,
  bool dark = false,
  bool markers = true,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenKey,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: [routeObserver],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          scaffoldBackgroundColor: dark
              ? const Color(0xff121212)
              : Colors.white,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: _Source(
          right: right,
          nested: nested,
          loaded: loaded,
          player: player,
          sourceVisible: sourceVisible,
          sourceTop: sourceTop,
          markers: markers,
        ),
      ),
    ),
  );
  await tester.pump();
  final source = tester.getRect(find.byKey(const ValueKey('card')));
  await tester.tap(find.byKey(const ValueKey('card')));
  await tester.pump();
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.setting = _MemorySettings();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aritxonly.hyperpiliplus/miuix_navigation'),
          (call) async {
            if (call.method == 'setBackdropSamplingPaused') {
              _samplingCalls.add(call.arguments as bool);
            }
            return null;
          },
        );
  });
  setUp(() {
    _pageCreations = 0;
    _controllerCreations = 0;
    _playerTaps = 0;
    _samplingCalls.clear();
  });
  tearDown(Get.reset);

  for (final right in [false, true]) {
    testWidgets(
      'painted skeleton follows expansion and contraction, right=$right',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = await _open(tester, right: right);
        for (final g in [0.10, 0.25, 0.50, 0.75, 1.0, 0.75, 0.50, 0.25, 0.10]) {
          await _seek(tester, g);
          final frame = VideoTransitionGeometry(
            source: source,
            viewport: const Size(400, 800),
            progress: _route.animation!.value,
          );
          final playerRect = tester.getRect(find.byKey(_playerKey));
          final expected = frame.mapRect(const Rect.fromLTWH(0, 24, 400, 225));
          expect(playerRect.left, closeTo(expected.left, 0.01));
          expect(playerRect.top, closeTo(expected.top, 0.01));
          expect(playerRect.width, closeTo(expected.width, 0.01));
          expect(playerRect.height, closeTo(expected.height, 0.01));
          final shot = await _pixels(
            tester,
            'skeleton-${right ? "right" : "left"}-${g.toStringAsFixed(2)}',
          );
          // Last skeleton bar is visible inside the expanding carrier already
          // at g=.10; testing widget presence / opacity alone cannot prove this.
          final skeleton = find.byKey(const ValueKey('ugc-intro-skeleton'));
          final bar = find
              .descendant(of: skeleton, matching: find.byType(Container))
              .last;
          final point = tester.getCenter(bar);
          expect(frame.container.contains(point), isTrue);
          final color =
              tester.widget<Container>(bar).decoration as BoxDecoration;
          expect(shot.at(point), color.color);
          if (g >= 0.5) {
            expect(shot.at(playerRect.center), _playerColor);
            expect(shot.magentaBounds(), isNull);
          }
        }
        expect(_pageCreations, 1);
        expect(_controllerCreations, 1);
        expect(find.byType(Hero), findsNothing);
        await _seek(tester, 1);
        await tester.tap(find.byKey(_playerKey));
        expect(_playerTaps, 1);
        Navigator.of(tester.element(find.byKey(_playerKey))).pop();
        await tester.pumpAndSettle();
        final returned = await _pixels(
          tester,
          'returned-${right ? "right" : "left"}',
        );
        expect(returned.magentaBounds(), isNotNull);
        expect(Get.isRegistered<_ProbeController>(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'source title keeps its aspect and hands off by geometric midpoint',
    (tester) async {
      await _open(tester);
      await _seek(tester, 0);
      final original = (await _pixels(tester)).magentaBounds()!;
      await _seek(tester, 0.25);
      final enlarged = (await _pixels(
        tester,
        'title-quarter',
      )).magentaBounds()!;
      final sx = enlarged.width / original.width;
      final sy = enlarged.height / original.height;
      expect((sx - sy).abs(), lessThan(0.13));
      expect(sx, inInclusiveRange(1.0, 1.4));
      final target = find
          .descendant(
            of: find.byType(VideoTransitionTargetPart),
            matching: find.text('KNOWN TITLE'),
          )
          .last;
      await _seek(tester, 0.40);
      final frame = await _pixels(tester, 'title-handoff');
      final sourceInk = frame.magentaBounds()!;
      final targetRect = tester.getRect(target);
      expect((sourceInk.top - targetRect.top).abs(), lessThan(18));
      await _seek(tester, 0.50);
      expect((await _pixels(tester)).magentaBounds(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final loadAt in [0.1, 0.4, 1.0]) {
    testWidgets(
      'data arriving at expansion=$loadAt preserves title and player',
      (
        tester,
      ) async {
        final player = ValueNotifier(_playerColor);
        final loaded = ValueNotifier(false);
        addTearDown(player.dispose);
        addTearDown(loaded.dispose);
        await _open(tester, loaded: loaded, player: player);
        await _seek(tester, loadAt);
        final titleBefore = tester.getRect(find.text('KNOWN TITLE').last);
        player.value = _readyColor;
        loaded.value = true;
        await tester.pump();
        final titleAfter = tester.getRect(find.text('KNOWN TITLE').last);
        expect(titleAfter.top, closeTo(titleBefore.top, 0.01));
        expect(titleAfter.size, titleBefore.size);
        if (loadAt < 0.4) await _seek(tester, 0.4);
        final image = await _pixels(tester, 'ready-at-$loadAt');
        expect(image.at(tester.getCenter(find.byKey(_playerKey))), _readyColor);
        expect(_pageCreations, 1);
        expect(_controllerCreations, 1);
      },
    );
  }

  for (final delay in [16, 120, 280, 600]) {
    for (final nested in [false, true]) {
      testWidgets('quick return at ${delay}ms, nested image Hero=$nested', (
        tester,
      ) async {
        final source = await _open(tester, nested: nested);
        await tester.pump(Duration(milliseconds: delay));
        var previous = tester.getRect(find.byKey(_playerKey));
        _route.navigator!.pop();
        await tester.pump();
        for (var i = 0; i < 30 && _route.isActive; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (!_route.isActive) break;
          final current = tester.getRect(find.byKey(_playerKey));
          expect(current.width, lessThanOrEqualTo(previous.width + 0.01));
          expect(current.height, lessThanOrEqualTo(previous.height + 0.01));
          previous = current;
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(const ValueKey('card'))), source);
        expect(Get.isRegistered<_ProbeController>(), isFalse);
        expect(_pageCreations, 1);
        expect(_controllerCreations, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'predictive back continues from current geometry, cancel=$cancel',
      (tester) async {
        await _open(tester);
        await tester.pumpAndSettle();
        final full = tester.getRect(find.byKey(_playerKey));
        final navigator = _route.navigator!;
        _route
          ..handleStartBackGesture(progress: 1)
          ..handleUpdateBackGestureProgress(progress: 0.55);
        await tester.pump();
        final dragged = tester.getRect(find.byKey(_playerKey));
        expect(dragged.width, lessThan(full.width));
        if (cancel) {
          _route.handleCancelBackGesture();
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byKey(_playerKey)), full);
          expect(navigator.userGestureInProgress, isFalse);
          _route
            ..handleStartBackGesture(progress: 1)
            ..handleUpdateBackGestureProgress(progress: 0.55);
          await tester.pump();
        }
        _route.handleCommitBackGesture();
        expect(_route.animation!.value, closeTo(0.55, 0.001));
        _route.handleCommitBackGesture();
        await tester.pump();
        var width = dragged.width;
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          final next = tester.getRect(find.byKey(_playerKey)).width;
          expect(next, lessThanOrEqualTo(width + 0.01));
          width = next;
        }
        await tester.pumpAndSettle();
        expect(navigator.userGestureInProgress, isFalse);
        expect(Get.isRegistered<_ProbeController>(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing source falls back without a stale shrinking target', (
    tester,
  ) async {
    final sourceVisible = ValueNotifier(true);
    addTearDown(sourceVisible.dispose);
    await _open(tester, sourceVisible: sourceVisible);
    await tester.pumpAndSettle();
    sourceVisible.value = false;
    await tester.pump();
    final full = tester.getRect(find.byKey(_playerKey));
    _route.navigator!.pop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(find.byKey(_playerKey)), full);
    await tester.pumpAndSettle();
    expect(Get.isRegistered<_ProbeController>(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets('media readiness uses real route progress, cancel=$cancel', (
      tester,
    ) async {
      await _open(tester, nested: true);
      bool? ready;
      final pending = waitForVideoPageEntry(_tag)
          .then((value) => ready = value);
      await tester.pump(const Duration(milliseconds: 32));
      expect(ready, isNull);
      if (cancel) _route.navigator!.pop();
      await tester.pumpAndSettle();
      await pending;
      expect(ready, !cancel);
      await tester.pumpWidget(const SizedBox());
      expect(await waitForVideoPageEntry(_tag), isTrue);
    });
  }

  testWidgets('large text retains uniform geometry and usable player', (
    tester,
  ) async {
    await _open(tester, textScale: 2);
    await _seek(tester, 0.25);
    expect((await _pixels(tester)).magentaBounds(), isNotNull);
    await _seek(tester, 1);
    await tester.tap(find.byKey(_playerKey));
    expect(_playerTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dark page, moving hit targets and early playback have no cover obstruction',
    (tester) async {
      await _open(tester, dark: true);
      await _seek(tester, 0.75);
      final image = await _pixels(tester, 'dark-three-quarters');
      final center = tester.getCenter(find.byKey(_playerKey));
      expect(image.at(center), _playerColor);
      await tester.tapAt(center);
      expect(_playerTaps, 1);
      _route.navigator!.pop();
      await tester.pumpAndSettle();
      expect(_samplingCalls.first, isTrue);
      expect(_samplingCalls.last, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('return title and cover use the updated source position', (
    tester,
  ) async {
    final top = ValueNotifier(340.0);
    addTearDown(top.dispose);
    await _open(tester, sourceTop: top);
    await tester.pumpAndSettle();
    top.value = 400;
    await tester.pump();
    _route.navigator!.pop();
    await tester.pump();
    await _seek(tester, 0.05);
    final image = await _pixels(tester, 'return-moved-source');
    expect(image.magentaBounds()!.top, greaterThan(480));
    _route.seek(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('card'))).dy, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic dynamic/history carrier preserves nested image Heroes', (
    tester,
  ) async {
    await _open(tester, nested: true, markers: false);
    await _seek(tester, 0.25);
    final quarter = tester.getRect(find.byKey(_playerKey)).width;
    expect(find.byType(Hero), findsOneWidget);
    await _seek(tester, 1);
    expect(tester.getRect(find.byKey(_playerKey)).width, greaterThan(quarter));
    _route.navigator!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsOneWidget);
    expect(_controllerCreations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'orientation changes retain the page and use a full-page return fallback',
    (tester) async {
      await _open(tester);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 400);
      await tester.pump();
      final full = tester.getRect(find.byKey(_playerKey));
      _route.navigator!.pop();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.byKey(_playerKey)), full);
      await tester.pumpAndSettle();
      expect(_pageCreations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final horizontal in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'actual card captures its painted parts: horizontal=$horizontal, scale=$scale',
        (tester) async {
          await tester.pumpWidget(
            GetMaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: horizontal ? 376 : 180,
                    height: horizontal ? 130 : 260,
                    child: horizontal
                        ? VideoCardH(videoItem: _HorizontalItem())
                        : VideoCardV(
                            videoItem: RcmdVideoItemModel.fromJson({
                              'id': 1,
                              'bvid': 'BV-test',
                              'cid': 1,
                              'goto': 'av',
                              'title': 'A long actual card title that wraps',
                              'duration': 60,
                              'pubdate': 1,
                              'owner': {'mid': 1, 'name': 'AUTHOR'},
                              'stat': {'view': 1, 'danmaku': 1},
                            }),
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.byType(VideoCardHero);
          final parts = tester.widgetList<VideoTransitionSourcePart>(
            find.byType(VideoTransitionSourcePart),
          );
          expect(
            parts.map((part) => part.part),
            containsAll([VideoTransitionPart.cover, VideoTransitionPart.title]),
          );
          final tag = tester.widget<VideoCardHero>(card).tag;
          final gesture = await tester.startGesture(tester.getCenter(card));
          expect(hasPendingVideoCardTransition(tag), isTrue);
          _route = _SeekableRoute(
            tag: tag,
            builder: (_) => _Details(tag: tag),
          );
          Navigator.of(tester.element(card)).push(_route);
          await gesture.cancel();
          await tester.pump();
          await _seek(tester, 0.25);
          final quarter = tester.getRect(find.byKey(_playerKey));
          await _seek(tester, 1);
          expect(
            tester.getRect(find.byKey(_playerKey)).width,
            greaterThan(quarter.width),
          );
          _route.navigator!.pop();
          await tester.pumpAndSettle();
          expect(find.byType(VideoCardHero), findsOneWidget);
          expect(Get.isRegistered<_ProbeController>(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _SeekableRoute extends VideoPageTransitionRoute<void> {
  _SeekableRoute({required super.builder, Object tag = _tag})
    : super(
        settings: RouteSettings(
          name: '/transition-probe',
          arguments: {'heroTag': tag},
        ),
      );
  void seek(double value) {
    controller!
      ..stop()
      ..value = value;
  }
}

class _Source extends StatelessWidget {
  const _Source({
    required this.right,
    required this.nested,
    this.loaded,
    this.player,
    this.sourceVisible,
    this.sourceTop,
    this.markers = true,
  });
  final bool right;
  final bool nested;
  final ValueNotifier<bool>? loaded;
  final ValueNotifier<Color>? player;
  final ValueNotifier<bool>? sourceVisible;
  final ValueNotifier<double>? sourceTop;
  final bool markers;

  @override
  Widget build(BuildContext context) {
    Widget mark(VideoTransitionPart part, Widget child) =>
        markers ? VideoTransitionSourcePart(part: part, child: child) : child;
    final card = SizedBox(
      key: const ValueKey('card'),
      width: 160,
      height: 184,
      child: VideoCardHero(
        tag: _tag,
        surfaceColor: Colors.white,
        child: GestureDetector(
          onTap: () {
            _route = _SeekableRoute(
              builder: (_) => _Details(loaded: loaded, player: player),
            );
            Navigator.of(context).push(_route);
          },
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark(
                  VideoTransitionPart.cover,
                  const SizedBox(
                    width: 160,
                    height: 90,
                    child: ColoredBox(color: Colors.orange),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: mark(
                    VideoTransitionPart.title,
                    const Text(
                      'SOURCE TITLE',
                      key: _sourceTitleKey,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Ahem',
                        color: _sourceInk,
                      ),
                    ),
                  ),
                ),
                if (nested)
                  const Hero(
                    tag: 'image-preview',
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: ColoredBox(color: Colors.teal),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    Widget positioned(double top) => Positioned(
      left: right ? 220 : 20,
      top: top,
      child: sourceVisible == null
          ? card
          : ValueListenableBuilder<bool>(
              valueListenable: sourceVisible!,
              builder: (_, visible, _) => visible ? card : const SizedBox(),
            ),
    );
    return Scaffold(
      backgroundColor: const Color(0xffcccccc),
      body: Stack(
        children: [
          if (sourceTop == null)
            positioned(340)
          else
            ValueListenableBuilder<double>(
              valueListenable: sourceTop!,
              builder: (_, top, _) => positioned(top),
            ),
        ],
      ),
    );
  }
}

class _Details extends StatefulWidget {
  const _Details({this.loaded, this.player, this.tag = _tag});
  final Object tag;
  final ValueNotifier<bool>? loaded;
  final ValueNotifier<Color>? player;
  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> with RouteAware, RouteAwareMixin {
  @override
  void initState() {
    super.initState();
    _pageCreations++;
    Get.put(_ProbeController());
  }

  Widget header(bool loaded) => loaded
      ? const UgcIntroHeader(
          owner: ColoredBox(color: Colors.teal),
          title: Text('KNOWN TITLE', style: TextStyle(fontSize: 16)),
        )
      : const UgcIntroLoadingSkeleton(title: 'KNOWN TITLE');

  @override
  Widget build(BuildContext context) => VideoPageHeroTarget(
    tag: widget.tag,
    surfaceColor: Theme.of(context).scaffoldBackgroundColor,
    child: Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 0,
            top: 24,
            width: 400,
            height: 225,
            child: VideoTransitionTargetPart(
              part: VideoTransitionPart.cover,
              child: GestureDetector(
                key: _playerKey,
                onTap: () => _playerTaps++,
                child: widget.player == null
                    ? const ColoredBox(color: _playerColor)
                    : ValueListenableBuilder<Color>(
                        valueListenable: widget.player!,
                        builder: (_, color, _) => ColoredBox(color: color),
                      ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 249,
            height: 36,
            child: VideoTransitionTargetPart(
              part: VideoTransitionPart.tabs,
              child: ColoredBox(
                color: Colors.cyan,
                child: Text('INTRO / COMMENTS'),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 300,
            child: widget.loaded == null
                ? header(false)
                : ValueListenableBuilder<bool>(
                    valueListenable: widget.loaded!,
                    builder: (_, loaded, _) => header(loaded),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _ProbeController extends GetxController {
  _ProbeController() {
    _controllerCreations++;
  }
}

class _MemorySettings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _HorizontalItem extends HorizontalVideoModel {
  _HorizontalItem() {
    aid = cid = 1;
    bvid = 'BV-test';
    title = 'MATCH highlighted actual horizontal title';
    titleList = [
      (isEm: true, text: 'MATCH '),
      (isEm: false, text: 'highlighted actual horizontal title'),
    ];
    owner = Owner.fromJson({'mid': 1, 'name': 'AUTHOR'});
    stat = Stat.fromJson({'view': 1, 'danmaku': 1});
    pubdate = 1;
    duration = 60;
  }
}
