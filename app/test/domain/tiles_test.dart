import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/domain/tiles.dart';

// Independent oracle: per-suit transfer states track sequences that began at
// the previous two ranks. It never chooses the first tile or enumerates melds.
bool oracleWins(List<int> tiles, int groups) {
  if (groups < 0 ||
      tiles.length != 3 * groups + 2 ||
      tiles.any((t) => t < 0 || t >= 34)) {
    return false;
  }
  final c = List.filled(34, 0);
  for (final t in tiles) {
    c[t]++;
  }
  if (c.any((n) => n > 4)) return false;
  bool suitWorks(List<int> ranks) {
    var states = <(int, int)>{(0, 0)};
    for (var rank = 0; rank < 9; rank++) {
      final next = <(int, int)>{};
      for (final state in states) {
        final spare = ranks[rank] - state.$1 - state.$2;
        for (var pungs = 0; pungs * 3 <= spare; pungs++) {
          final starts = spare - pungs * 3;
          if (rank < 7 || starts == 0) next.add((state.$2, starts));
        }
      }
      states = next;
    }
    return states.contains((0, 0));
  }

  for (var pair = 0; pair < 34; pair++) {
    if (c[pair] < 2) continue;
    c[pair] -= 2;
    final valid =
        c.sublist(27).every((n) => n % 3 == 0) &&
        [0, 9, 18].every((s) => suitWorks(c.sublist(s, s + 9)));
    c[pair] += 2;
    if (valid) return true;
  }
  return false;
}

List<int> generatedWin(Random random, int groups) {
  while (true) {
    final pair = random.nextInt(34);
    final hand = <int>[pair, pair];
    for (var i = 0; i < groups; i++) {
      if (random.nextBool()) {
        final t = random.nextInt(34);
        hand.addAll([t, t, t]);
      } else {
        final t = random.nextInt(3) * 9 + random.nextInt(7);
        hand.addAll([t, t + 1, t + 2]);
      }
    }
    if (hand.every((t) => hand.where((n) => t == n).length <= 4)) return hand;
  }
}

void main() {
  group('notation and immutable input', () {
    test('every canonical tile has a reversible code', () {
      for (var t = 0; t < 42; t++) {
        expect(parseTiles(tileCode(t)), [t]);
      }
      expect(parseTiles('123m 456p\n789s 1234567z 12345678f').length, 24);
      expect(parseTiles(''), isEmpty);
      for (final bad in ['0m', '8z', '9f', '123', 'm', '-1m', '1x', '1m!']) {
        expect(() => parseTiles(bad), throwsFormatException, reason: bad);
      }
      expect(() => tileCode(-1), throwsRangeError);
      expect(() => tileCode(42), throwsRangeError);
      expect(isTerminal(-9), isFalse);
      expect(isTerminal(27), isFalse);
    });
    test('meld owns its tiles and round-trips', () {
      final input = [1, 1, 1, 1];
      final m = Meld(MeldKind.closedKong, input);
      input.clear();
      expect(m.tiles, [1, 1, 1, 1]);
      expect(() => m.tiles.add(0), throwsUnsupportedError);
      expect(Meld.fromJson(m.toJson()).toJson(), m.toJson());
    });
  });
  group('winning decomposition boundaries', () {
    test('pair-only, cross-suit, count and special-shape cases', () {
      expect(decompose([0, 0], 0).length, 1);
      expect(decompose([0, 1], 0), isEmpty);
      expect(decompose([0, 0], -1), isEmpty);
      expect(decompose([34, 34], 0), isEmpty);
      expect(decompose(parseTiles('789m123p123s11122z'), 4), isNotEmpty);
      expect(decompose(parseTiles('891m123p123s11122z'), 4), isEmpty);
      expect(decompose(parseTiles('11111m123p123s111z'), 4), isEmpty);
      expect(decompose(parseTiles('112233m445566p77z'), 4), isNotEmpty);
      expect(decompose(parseTiles('11m22p33s11223344z'), 4), isEmpty);
      expect(isThirteenOrphans(parseTiles('19m19p19s1234567z1m')), isTrue);
      expect(isThirteenOrphans(parseTiles('19m19p19s1234566z1m')), isFalse);
    });
    test('ambiguous hand returns all legal partitions without mutation', () {
      final hand = parseTiles('11122233344455m');
      final before = List.of(hand);
      final results = decompose(hand, 4);
      expect(results.length, greaterThan(1));
      expect(
        results.any((d) => d.groups.every((m) => m.kind == MeldKind.pung)),
        isTrue,
      );
      expect(
        results.any((d) => d.groups.any((m) => m.kind == MeldKind.chow)),
        isTrue,
      );
      expect(hand, before);
      final keys = results.map(
        (d) => '${d.pair}:${d.groups.map((m) => m.tiles.join(',')).join('/')}',
      );
      expect(keys.toSet().length, results.length);
    });
    test('6000 seeded inputs agree with independent transfer-state oracle', () {
      final random = Random(0x4d41484a);
      for (var i = 0; i < 6000; i++) {
        final groups = i % 6;
        List<int> hand;
        if (i < 1000) {
          hand = generatedWin(random, groups);
        } else if (i < 2000) {
          hand = generatedWin(random, groups);
          hand[random.nextInt(hand.length)] = random.nextInt(34);
        } else {
          hand = List.generate(groups * 3 + 2, (_) => random.nextInt(34));
        }
        final snapshot = List.of(hand);
        final expected = oracleWins(hand, groups);
        final results = decompose(hand, groups);
        expect(results.isNotEmpty, expected, reason: 'seed case $i: $hand');
        expect(hand, snapshot);
        final sorted = List.of(hand)..sort();
        for (final d in results) {
          final reconstructed = [
            d.pair,
            d.pair,
            ...d.groups.expand((m) => m.tiles),
          ]..sort();
          expect(reconstructed, sorted);
          expect(d.groups.length, groups);
        }
        hand.shuffle(random);
        expect(decompose(hand, groups).isNotEmpty, expected);
      }
    });
  });
}
