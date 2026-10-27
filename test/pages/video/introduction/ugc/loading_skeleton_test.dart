import 'package:PiliPlus/pages/video/introduction/ugc/loading_skeleton.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'resolved metadata fades in without painting the outgoing title',
    (
      tester,
    ) async {
      final loaded = ValueNotifier(false);
      addTearDown(loaded.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: loaded,
              builder: (_, ready, _) => UgcIntroContent(
                loading: !ready,
                title: 'KNOWN TITLE',
                child: const UgcIntroHeader(
                  owner: Text('AUTHOR'),
                  title: Text('KNOWN TITLE', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
        ),
      );
      final titleBefore = tester.getTopLeft(find.text('KNOWN TITLE'));
      loaded.value = true;
      await tester.pump();
      expect(find.byKey(const ValueKey('ugc-intro-skeleton')), findsNothing);
      expect(
        find.byKey(const ValueKey('ugc-intro-skeleton'), skipOffstage: false),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 70));
      final fades = tester.widgetList<FadeTransition>(
        find.byType(FadeTransition),
      );
      expect(
        fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      expect(tester.getTopLeft(find.text('KNOWN TITLE').last), titleBefore);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ugc-intro-skeleton')), findsNothing);
      expect(find.text('AUTHOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
      'loading and resolved slots preserve title geometry, scale=$scale',
      (tester) async {
        Future<void> mount(bool loaded) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 360,
                    child: loaded
                        ? const UgcIntroHeader(
                            owner: Text('Author\nInformation'),
                            title: Text(
                              'KNOWN TITLE',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : const UgcIntroLoadingSkeleton(title: 'KNOWN TITLE'),
                  ),
                ),
              ),
            ),
          );
        }

        await mount(false);
        final before = tester.getRect(find.text('KNOWN TITLE'));
        await mount(true);
        expect(tester.getRect(find.text('KNOWN TITLE')), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('shows the known title immediately and supports replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UgcIntroLoadingSkeleton(title: '已有标题')),
      ),
    );
    expect(find.text('已有标题'), findsOneWidget);
    expect(find.byKey(const ValueKey('ugc-intro-skeleton')), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('真实详情'))),
    );
    expect(find.byKey(const ValueKey('ugc-intro-skeleton')), findsNothing);
    expect(find.text('真实详情'), findsOneWidget);
  });
  testWidgets('unknown title shows placeholders without invented text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UgcIntroLoadingSkeleton(title: null)),
      ),
    );
    expect(find.byKey(const ValueKey('ugc-intro-skeleton')), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
