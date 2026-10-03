import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/data/local_store.dart';
import 'package:mahjong_vision/domain/scoring.dart';
import 'package:mahjong_vision/domain/tiles.dart';
import 'package:mahjong_vision/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalStore> launch(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Map<String, Object> initialValues = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(initialValues);
  // Native camera recovery is exercised on a device; there is no lost photo in UI tests.
  const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pickerChannel,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      null,
    ),
  );
  final store = LocalStore(await SharedPreferences.getInstance());
  await tester.pumpWidget(MahjongApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

Future<void> scrollTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).last,
    maxScrolls: 35,
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String label) async {
  final target = find.text(label);
  await scrollTo(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> sample(WidgetTester tester) async {
  await tapVisible(tester, '先用示範手牌試算 →');
  expect(find.text('暗手牌  14 / 14'), findsOneWidget);
}

SavedHand savedSample(Rules rules) {
  final hand = Hand(
    concealed: parseTiles('123456789m123p55s'),
    winningTile: 22,
    source: WinSource.selfDraw,
    circumstancesConfirmed: true,
  );
  return SavedHand.capture(hand, rules, scoreHand(hand, rules));
}

void main() {
  testWidgets('new bilingual brand fits a narrow phone', (tester) async {
    await launch(tester, size: const Size(320, 568));
    expect(find.text('開心計一番'), findsOneWidget);
    expect(find.text('Point of Happiness'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'visible correction button opens the tile editor without long press',
    (tester) async {
      await launch(tester);
      await sample(tester);
      await tapVisible(tester, '更正牌面');
      expect(find.text('選擇要更正的牌'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('choose-correction-0')));
      await tester.pumpAndSettle();
      expect(find.text('更正 一萬'), findsOneWidget);
      await tester.tap(find.text('刪除這一張'));
      await tester.pumpAndSettle();
      expect(find.text('暗手牌  13 / 14'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('sample confirms, scores, saves and reopens', (tester) async {
    final store = await launch(tester);
    await sample(tester);
    await tapVisible(tester, '已核對牌面及本局情況');
    await tapVisible(tester, '計算番數與支付');
    expect(find.text('這副牌，算好了。'), findsOneWidget);
    expect(find.text('+48'), findsOneWidget);
    await tapVisible(tester, '儲存本手記錄');
    expect(find.text('已儲存在這部手機'), findsOneWidget);
    expect(store.readHistory(), hasLength(1));
    expect(store.readHistory().single.result['balances'], [48, -16, -16, -16]);
    await tapVisible(tester, '返回修改');
    await tester.tap(find.text('記錄'));
    await tester.pumpAndSettle();
    expect(find.text('香港牌 · 自摸'), findsOneWidget);
    await tester.tap(find.text('香港牌 · 自摸'));
    await tester.pumpAndSettle();
    expect(find.text('已儲存的牌局'), findsOneWidget);
    expect(find.text('玩家 B → 玩家 A'), findsOneWidget);
  });
  testWidgets('unconfirmed facts give no payments or save action', (
    tester,
  ) async {
    final store = await launch(tester);
    await sample(tester);
    await tapVisible(tester, '計算番數與支付');
    expect(find.text('還需要核對一下'), findsOneWidget);
    expect(find.text('每位玩家支付'), findsNothing);
    expect(find.text('儲存本手記錄'), findsNothing);
    expect(store.readHistory(), isEmpty);
  });
  testWidgets('changing context revokes confirmation', (tester) async {
    await launch(tester);
    await sample(tester);
    await tapVisible(tester, '已核對牌面及本局情況');
    await tapVisible(tester, '出銃');
    await scrollTo(tester, find.text('已核對牌面及本局情況'));
    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '已核對牌面及本局情況'),
    );
    expect(checkbox.value, isFalse);
    await tapVisible(tester, '計算番數與支付');
    expect(find.text('還需要核對一下'), findsOneWidget);
    expect(find.text('每位玩家支付'), findsNothing);
  });
  testWidgets('settings update persist through a new app instance', (
    tester,
  ) async {
    final store = await launch(tester);
    await tester.tap(find.text('規則'));
    await tester.pumpAndSettle();
    await tapVisible(tester, '台灣牌 · 16 張家規');
    expect(store.readRules().family, RuleFamily.taiwanese);
    await scrollTo(tester, find.text('每台'));
    final row = find.widgetWithText(ListTile, '每台');
    await tester.tap(
      find.descendant(of: row, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '20');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    expect(store.readRules().unit, 20);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MahjongApp(store: LocalStore(await SharedPreferences.getInstance())),
    );
    await tester.pumpAndSettle();
    expect(find.text('台灣 16 張'), findsOneWidget);
    expect(store.readRules().unit, 20);
  });
  testWidgets('disabling flowers clears selected flowers and confirmation', (
    tester,
  ) async {
    await launch(tester);
    await sample(tester);
    await tapVisible(tester, '春①');
    await tapVisible(tester, '已核對牌面及本局情況');
    await tester.tap(find.text('規則'));
    await tester.pumpAndSettle();
    await tapVisible(tester, '使用花牌');
    await tester.tap(find.text('手牌'));
    await tester.pumpAndSettle();
    expect(find.text('春①'), findsNothing);
    await scrollTo(tester, find.text('已核對牌面及本局情況'));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '已核對牌面及本局情況'),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.text('規則'));
    await tester.pumpAndSettle();
    await tapVisible(tester, '使用花牌');
    await tester.tap(find.text('手牌'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('春①'));
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '春①')).selected,
      isFalse,
    );
  });

  testWidgets('different payment units do not mix in history totals', (
    tester,
  ) async {
    final one = savedSample(Rules());
    final two = savedSample(Rules().copyWith(unit: 2));
    await launch(
      tester,
      initialValues: {
        'history.v1': jsonEncode([one.toJson(), two.toJson()]),
      },
    );
    await tester.tap(find.text('記錄'));
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('目前規則的累計收支'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: card, matching: find.text('+48')),
      findsOneWidget,
    );
    expect(find.text('+144'), findsNothing);
    expect(find.text('香港牌 · 自摸'), findsNWidgets(2));
  });

  testWidgets('equivalent override order stays in the same history total', (
    tester,
  ) async {
    final old = Rules().copyWith(overrides: {'selfDraw': 2, 'noFlowers': 1});
    final current = Rules().copyWith(
      overrides: {'noFlowers': 1, 'selfDraw': 2},
    );
    final saved = savedSample(old);
    await launch(
      tester,
      initialValues: {
        'history.v1': jsonEncode([saved.toJson()]),
        'rules.v1': jsonEncode(current.toJson()),
      },
    );
    await tester.tap(find.text('記錄'));
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('目前規則的累計收支'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('+${saved.result['total']}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting then undoing a hand restores persisted history', (
    tester,
  ) async {
    final saved = savedSample(Rules());
    final store = await launch(
      tester,
      initialValues: {
        'history.v1': jsonEncode([saved.toJson()]),
      },
    );
    await tester.tap(find.text('記錄'));
    await tester.pumpAndSettle();
    await tapVisible(tester, '香港牌 · 自摸');
    await tapVisible(tester, '移除這手記錄');
    expect(store.readHistory(), isEmpty);
    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();
    expect(store.readHistory().single.id, saved.id);
    expect(find.text('香港牌 · 自摸'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 780),
    const Size(390, 844),
    const Size(768, 844),
  ]) {
    testWidgets('pages fit ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await launch(tester, size: size);
      expect(tester.takeException(), isNull);
      for (final tab in ['手牌', '記錄', '規則', '掃描']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab at $size');
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'scrolled $tab at $size',
        );
      }
    });
  }
}
