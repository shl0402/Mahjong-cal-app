import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/data/local_store.dart';
import 'package:mahjong_vision/domain/scoring.dart';
import 'package:mahjong_vision/domain/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedHand snapshot() {
  final hand = Hand(
    concealed: parseTiles('123456789m123p55s'),
    winningTile: 22,
    source: WinSource.selfDraw,
    circumstancesConfirmed: true,
  );
  final rules = Rules();
  return SavedHand.capture(hand, rules, scoreHand(hand, rules));
}

Map<String, dynamic> mutableSnapshot() =>
    jsonDecode(jsonEncode(snapshot().toJson()));

Future<LocalStore> storeWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return LocalStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('local settings', () {
    test('new install has usable defaults and empty history', () async {
      final store = await storeWith({});
      expect(store.readRules().family, RuleFamily.hongKong);
      expect(store.readRules().minimum, 3);
      expect(store.readHistory(), isEmpty);
      expect(store.warning, isNull);
    });
    test('custom settings survive save and a new store instance', () async {
      final store = await storeWith({});
      final expected = Rules.taiwanese().copyWith(
        minimum: 2,
        cap: 32,
        flowers: false,
        base: 100,
        unit: 20,
        payment: PaymentMode.splitTotal,
        overrides: {'selfDraw': 2},
      );
      await store.saveRules(expected);
      expect(
        LocalStore(await SharedPreferences.getInstance()).readRules().toJson(),
        expected.toJson(),
      );
    });
    final corruptRules = <String, Object>{
      'broken JSON': '{not valid',
      'wrong storage type': 42,
      'wrong JSON root': jsonEncode([1, 2, 3]),
      'invalid range': jsonEncode({...Rules().toJson(), 'unit': -10}),
      'unknown family': jsonEncode({...Rules().toJson(), 'family': 'missing'}),
      'missing fields': jsonEncode({'family': 'hongKong'}),
    };
    for (final entry in corruptRules.entries) {
      test('${entry.key} falls back and retains original bytes', () async {
        final store = await storeWith({'rules.v1': entry.value});
        expect(store.readRules().toJson(), Rules().toJson());
        expect(store.warning, isNotNull);
        expect(store.prefs.get('rules.v1'), entry.value);
      });
    }
  });
  group('saved score snapshots', () {
    test('incomplete and unverified results cannot enter history', () {
      for (final status in ResultStatus.values.where(
        (s) => s != ResultStatus.valid,
      )) {
        expect(
          () => SavedHand.capture(Hand(), Rules(), ScoreResult(status)),
          throwsArgumentError,
        );
      }
    });
    test('roundtrip retains hand, exact rules, score and payments', () {
      final saved = snapshot();
      final restored = SavedHand.fromJson(
        jsonDecode(jsonEncode(saved.toJson())),
      );
      expect(restored.toJson(), saved.toJson());
      expect(restored.result['engineVersion'], Rules.version);
      expect(restored.result['score'], 3);
      expect(restored.result['total'], 48);
      expect(restored.result['balances'], [48, -16, -16, -16]);
    });
    test('constructor owns nested inputs', () {
      final original = mutableSnapshot();
      final saved = SavedHand(
        original['id'],
        original['date'],
        original['hand'],
        original['rules'],
        original['result'],
      );
      original['hand']['concealed'][0] = 26;
      original['result']['transfers'][0]['amount'] = 999;
      original['rules']['overrides']['selfDraw'] = 99;
      expect(saved.hand['concealed'][0], 0);
      expect(saved.result['transfers'][0]['amount'], 16);
      expect(saved.rules['overrides'], isEmpty);
    });
    test('deserialization owns nested inputs', () {
      final original = mutableSnapshot();
      final saved = SavedHand.fromJson(original);
      original['hand']['concealed'][0] = 26;
      original['result']['balances'][0] = 123456;
      expect(saved.hand['concealed'][0], 0);
      expect(saved.result['balances'][0], 48);
    });
    test('snapshot maps and nested collections cannot be edited in place', () {
      final saved = snapshot();
      expect(() => saved.result['score'] = 9, throwsUnsupportedError);
      expect(() => saved.hand['concealed'][0] = 26, throwsUnsupportedError);
      expect(
        () => saved.result['transfers'][0]['amount'] = 1000,
        throwsUnsupportedError,
      );
      expect(
        () => saved.toJson()['result']['balances'][0] = 999,
        throwsUnsupportedError,
      );
      expect(saved.result['balances'][0], 48);
    });
    test(
      'settings changes never recalculate previously saved payments',
      () async {
        final store = await storeWith({});
        await store.saveHistory([snapshot()]);
        await store.saveRules(Rules().copyWith(unit: 100, cap: 8));
        final history = store.readHistory();
        expect(history, hasLength(1));
        expect(history.single.result['total'], 48);
        expect(history.single.rules['unit'], 1);
        expect(store.readRules().unit, 100);
      },
    );
    test('historical engine version is retained rather than rewritten', () {
      final original = mutableSnapshot();
      original['result']['engineVersion'] = 'previous-engine';
      expect(
        SavedHand.fromJson(original).result['engineVersion'],
        'previous-engine',
      );
    });
    test('saving empty history survives reopening', () async {
      final store = await storeWith({});
      await store.saveHistory([snapshot()]);
      await store.saveHistory([]);
      expect(
        LocalStore(await SharedPreferences.getInstance()).readHistory(),
        isEmpty,
      );
    });
  });
  group('corrupt history recovery', () {
    final changes = <String, void Function(Map<String, dynamic>)>{
      'missing balances': (j) => j['result'].remove('balances'),
      'wrong balance types': (j) => j['result']['balances'] = ['x', 0, 0, 0],
      'incorrect balance length': (j) => j['result']['balances'] = [48, -48],
      'unbalanced ledger': (j) =>
          j['result']['balances'] = [100, -16, -16, -16],
      'invalid date': (j) => j['date'] = 'x',
      'malformed tiles': (j) => j['hand']['concealed'] = ['bad'],
      'invalid tile identity': (j) => j['hand']['concealed'][0] = 100,
      'unknown preset': (j) => j['rules']['family'] = 'missing',
      'missing win source': (j) => j['hand']['source'] = null,
      'negative transfer': (j) => j['result']['transfers'][0]['amount'] = -16,
    };
    for (final entry in changes.entries) {
      test('${entry.key} rejected before the UI reads it', () async {
        final json = mutableSnapshot();
        entry.value(json);
        final raw = jsonEncode([json]);
        final store = await storeWith({'history.v1': raw});
        expect(store.readHistory(), isEmpty);
        expect(store.warning, isNotNull);
        expect(store.prefs.getString('history.v1'), raw);
      });
    }
    for (final raw in ['not json', '{}', '[1]', '[null]']) {
      test('invalid structure $raw preserves original', () async {
        final store = await storeWith({'history.v1': raw});
        expect(store.readHistory(), isEmpty);
        expect(store.warning, isNotNull);
        expect(store.prefs.getString('history.v1'), raw);
      });
    }
    test('one damaged entry does not hide valid entries', () async {
      final saved = snapshot();
      final raw = jsonEncode([
        saved.toJson(),
        {'broken': true},
      ]);
      final store = await storeWith({'history.v1': raw});
      expect(store.readHistory().single.id, saved.id);
      expect(store.warning, isNotNull);
      expect(store.prefs.getString('history.v1'), raw);
    });
    test(
      'a later save backs up damaged original before replacing it',
      () async {
        const damaged = '[broken';
        final store = await storeWith({'history.v1': damaged});
        expect(store.readHistory(), isEmpty);
        await store.saveHistory([snapshot()]);
        final backups = store.prefs.getKeys().where(
          (k) => k.startsWith('history.v1.recovery.'),
        );
        expect(backups, hasLength(1));
        expect(store.prefs.getString(backups.single), damaged);
        expect(store.readHistory(), hasLength(1));
      },
    );
  });
}
