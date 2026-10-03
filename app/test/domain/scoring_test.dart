import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/domain/scoring.dart';
import 'package:mahjong_vision/domain/tiles.dart';

import 'tiles_test.dart' show generatedWin;

Hand hand(
  String notation, {
  int? win,
  WinSource source = WinSource.discard,
  List<Meld> melds = const [],
  List<int> flowers = const [],
  int winner = 1,
  int dealer = 0,
  int discarder = 2,
  int roundWind = 2,
  int continuations = 0,
  Replacement replacement = Replacement.none,
  int kongChain = 0,
  LastTile lastTile = LastTile.none,
  int? liablePlayer,
  bool heavenly = false,
  bool earthly = false,
}) {
  final tiles = parseTiles(notation);
  return Hand(
    concealed: tiles,
    winningTile: win ?? tiles.last,
    source: source,
    melds: melds,
    flowers: flowers,
    winner: winner,
    dealer: dealer,
    discarder: discarder,
    roundWind: roundWind,
    continuations: continuations,
    replacement: replacement,
    kongChain: kongChain,
    lastTile: lastTile,
    liablePlayer: liablePlayer,
    heavenly: heavenly,
    earthly: earthly,
    circumstancesConfirmed: true,
  );
}

Set<String> ids(ScoreResult result) => result.patterns.map((p) => p.id).toSet();
ScoreResult hk(Hand h, [Rules? rules]) => scoreHand(h, rules ?? Rules());

void main() {
  group('HKMA ordinary scoring fixtures (original hands)', () {
    test('minimum distinguishes same hand on discard and self draw', () {
      final discard = hk(hand('123456789m123p55s'));
      expect(discard.status, ResultStatus.belowMinimum);
      expect(discard.score, 2);
      expect(discard.transfers, isEmpty);
      final drawn = hk(hand('123456789m123p55s', source: WinSource.selfDraw));
      expect(drawn.status, ResultStatus.valid);
      expect(drawn.score, 3);
      expect(ids(drawn), {'chows', 'noFlowers', 'selfDraw'});
      expect(drawn.transfers.map((t) => t.amount), [16, 16, 16]);
    });
    test('half flush; double wind; identical seat/round both count', () {
      expect(hk(hand('123456789m11122z')).score, 4);
      final east = hk(hand('123456789m11122z', winner: 0, roundWind: 0));
      expect(east.score, 6);
      expect(ids(east), {'halfFlush', 'seatWind', 'roundWind', 'noFlowers'});
    });
    test('pungs and dragon; discard-completed pung is not hidden', () {
      final result = hk(hand('111m222p333s55566z', win: 20));
      expect(result.score, 5);
      expect(ids(result), {'allPungs', 'dragon', 'noFlowers'});
    });
    test('small/big dragons add individual dragon points in HK', () {
      final small = hk(hand('123m456p55566677z'));
      expect(small.score, 6);
      expect(small.patterns.where((p) => p.id == 'dragon').length, 2);
      final big = hk(hand('123m55566677722z'));
      // Three dragon bonuses plus 5 for big dragons, 3 for half flush and
      // 1 for no flowers. Ordinary patterns stack, then the ten-faan cap applies.
      expect(big.rawScore, 12);
      expect(big.score, 10);
      expect(big.patterns.where((p) => p.id == 'dragon').length, 3);
    });
    test('mixed terminals stacks with all pungs', () {
      final result = hk(hand('111999m111p11122z', win: 0));
      expect(result.score, 5);
      expect(ids(result), {'allPungs', 'mixedTerminals', 'noFlowers'});
    });
    test('four chows accepts honor eye and pair completion', () {
      final result = hk(hand('123456789m123p55z', source: WinSource.selfDraw));
      expect(ids(result), contains('chows'));
      expect(result.score, 3);
    });
    test('flower set adds its matching flower; numbered flower mapping', () {
      final result = hk(
        hand(
          '123456789m123p55s',
          source: WinSource.selfDraw,
          flowers: [34, 35, 36, 37],
        ),
      );
      expect(result.score, 4);
      expect(ids(result), {'chows', 'selfDraw', 'seatFlower', 'flowerSet'});
      for (var seat = 0; seat < 4; seat++) {
        final flower = hk(
          hand(
            '123456789m123p55s',
            source: WinSource.selfDraw,
            winner: seat,
            flowers: [38 + seat],
          ),
        );
        expect(
          flower.patterns.singleWhere((p) => p.id == 'seatFlower').value,
          1,
        );
      }
    });
    test('closed bonus only in no-flower rules and never after a kong', () {
      final rules = Rules(flowers: false);
      final result = hk(
        hand('123456789m123p55s', source: WinSource.selfDraw),
        rules,
      );
      expect(ids(result), {'chows', 'selfDraw', 'closed'});
      final kong = hk(
        hand(
          '123m456p789s22z',
          melds: [
            Meld(MeldKind.closedKong, [31, 31, 31, 31]),
          ],
        ),
        rules,
      );
      expect(ids(kong), isNot(contains('closed')));
      expect(ids(kong), isNot(contains('noFlowers')));
    });
    test('last live draw adds 1; last discard adds nothing', () {
      final drawn = hk(
        hand(
          '123456789m123p55s',
          source: WinSource.selfDraw,
          lastTile: LastTile.draw,
        ),
      );
      expect(drawn.score, 4);
      final discarded = hk(
        hand('123456789m123p55s', lastTile: LastTile.discard),
      );
      expect(discarded.score, 2);
      expect(ids(discarded), isNot(contains('lastDraw')));
    });
    test('flower replacement is not a HK kong win', () {
      final flower = hk(
        hand(
          '123456789m123p55s',
          source: WinSource.selfDraw,
          flowers: [35],
          replacement: Replacement.flower,
        ),
      );
      expect(flower.score, 3);
      expect(ids(flower), isNot(contains('kongWin')));
      final kong = hk(
        hand(
          '123m456p789s22z',
          source: WinSource.selfDraw,
          melds: [
            Meld(MeldKind.closedKong, [31, 31, 31, 31]),
          ],
          replacement: Replacement.kong,
          kongChain: 1,
        ),
      );
      expect(kong.score, 4);
      expect(ids(kong), contains('kongWin'));
    });
    test('rob added kong adds a point and uses total self draw payment', () {
      final result = hk(
        hand('123456789m123p55s', win: 0, source: WinSource.robAddedKong),
      );
      expect(result.score, 3);
      expect(result.total, 48);
      expect(result.transfers.single.from, 2);
      expect(ids(result), isNot(contains('selfDraw')));
    });
  });
  group('HKMA limits, ambiguity and near misses', () {
    final limits = <String, (String, int)>{
      'allHonors': ('11122255566677z', 32),
      'smallWinds': ('111222333z456m44z', 30),
      'bigWinds': ('111222333444z55m', 4),
      'allTerminals': ('111999m111999p11s', 0),
      'fourHidden': ('111m222p333s55566z', 32),
      'orphans': ('19m19p19s1234567z1m', 0),
      'nineGates': ('11123456789995m', 4),
    };
    for (final fixture in limits.entries) {
      test('${fixture.key} is a single fixed limit', () {
        final result = hk(hand(fixture.value.$1, win: fixture.value.$2));
        expect(result.status, ResultStatus.valid);
        expect(result.score, 10);
        expect(ids(result), {fixture.key});
        expect(result.total, 512);
      });
    }
    test('nine gates discard requires nine-sided pre-win shape; self draw does not', () {
      expect(
        ids(hk(hand('11123456789995m', win: 0))),
        isNot(contains('nineGates')),
      );
      expect(
        ids(hk(hand('11123456789995m', win: 0, source: WinSource.selfDraw))),
        {'nineGates'},
      );
    });
    test('concealed kong disqualifies four hidden HK limit', () {
      final result = hk(
        hand(
          '222p333s55566z',
          melds: [
            Meld(MeldKind.closedKong, [0, 0, 0, 0]),
          ],
        ),
      );
      expect(ids(result), isNot(contains('fourHidden')));
      expect(result.score, 5);
    });
    test('all four declared kongs and two consecutive replacement kongs', () {
      final four = hk(
        hand(
          '55s',
          melds: [
            for (final t in [0, 9, 18, 31])
              Meld(MeldKind.closedKong, [t, t, t, t]),
          ],
        ),
      );
      expect(ids(four), {'fourKongs'});
      final chain = hk(
        hand(
          '123m456p55s',
          source: WinSource.selfDraw,
          melds: [
            for (final t in [31, 32]) Meld(MeldKind.closedKong, [t, t, t, t]),
          ],
          replacement: Replacement.kong,
          kongChain: 2,
        ),
      );
      expect(ids(chain), {'doubleKongWin'});
    });
    test('initial wins require declared circumstances', () {
      expect(
        ids(
          hk(
            hand(
              '123456789m123p55s',
              source: WinSource.selfDraw,
              winner: 0,
              heavenly: true,
            ),
          ),
        ),
        {'heavenly'},
      );
      expect(ids(hk(hand('123456789m123p55s', discarder: 0, earthly: true))), {
        'earthly',
      });
      expect(
        hk(hand('123456789m123p55s', heavenly: true)).status,
        ResultStatus.invalid,
      );
    });
    test('ambiguous hand maximizes score over legal partitions', () {
      expect(hk(hand('11122233344455m')).score, 10);
      expect(ids(hk(hand('11122233344455m'))), {'fourHidden'});
    });
    test(
      'only orphans may rob concealed kong; other player retains three copies',
      () {
        final valid = hk(
          hand(
            '19m19p19s1234567z1m',
            win: 27,
            source: WinSource.robConcealedKong,
          ),
        );
        expect(valid.status, ResultStatus.valid);
        expect(valid.total, 768);
        expect(
          hk(
            hand(
              '123456789m123p55s',
              win: 0,
              source: WinSource.robConcealedKong,
            ),
          ).status,
          ResultStatus.invalid,
        );
        expect(
          hk(
            hand(
              '19m19p19s1234567z1m',
              win: 0,
              source: WinSource.robConcealedKong,
            ),
          ).status,
          ResultStatus.invalid,
        );
        expect(
          hk(hand('123456789m123p55s', win: 22, source: WinSource.robAddedKong))
              .status,
          ResultStatus.invalid,
        );
      },
    );
    test('custom cap and values; override of 10 is not an automatic limit', () {
      final capped = hk(hand('11122233344455m'), Rules(cap: 8));
      expect(capped.rawScore, 10);
      expect(capped.score, 8);
      expect(capped.total, 256);
      final changed = hk(
        hand('123456789m123p55s'),
        Rules(overrides: {'chows': 10}),
      );
      expect(changed.rawScore, 11);
      expect(changed.score, 10);
      expect(changed.excluded, isEmpty);
    });
  });
  group('explicit Taiwanese 16-tile house contract', () {
    final rules = Rules.taiwanese();
    test('17 tiles and closed self draw are distinct from 14 tile HK', () {
      final h = hand('123456789m123456p55s', source: WinSource.selfDraw);
      final result = scoreHand(h, rules);
      expect(result.status, ResultStatus.valid);
      expect(ids(result), {'closedSelfDraw', 'singleWait'});
      expect(result.score, 4);
      expect(hk(h).status, ResultStatus.invalid);
      expect(
        scoreHand(hand('123456789m123p55s'), rules).status,
        ResultStatus.incomplete,
      );
    });
    test('pair-completed multi-wait is not Taiwanese flat hand', () {
      final result = scoreHand(hand('12344m123456p123456s', win: 3), rules);
      expect(result.status, ResultStatus.valid);
      expect(result.score, 1);
      expect(ids(result), {'closed'});
    });
    test('non-single chow completion counts flat hand', () {
      final result = scoreHand(hand('123456789m123456p55s', win: 0), rules);
      expect(ids(result), {'chows', 'closed'});
      expect(result.score, 3);
    });
    test(
      'small dragons replace separate dragon points; hidden tiers do not stack',
      () {
        final result = scoreHand(
          hand('111m222p333s55566677z', source: WinSource.selfDraw),
          rules,
        );
        expect(ids(result), {
          'allPungs',
          'smallDragons',
          'closedSelfDraw',
          'fiveConcealed',
          'singleWait',
        });
        expect(result.score, 20);
        expect(ids(result), isNot(contains('dragon')));
        final discarded = scoreHand(
          hand('111m222p333s55566677z', win: 20),
          rules,
        );
        expect(ids(discarded), {
          'allPungs',
          'smallDragons',
          'closed',
          'fourConcealed',
        });
        expect(discarded.score, 14);
      },
    );
    test('flower replacement counts; no no-flower bonus', () {
      final result = scoreHand(
        hand(
          '123456789m123456p55s',
          source: WinSource.selfDraw,
          replacement: Replacement.flower,
          flowers: [35],
        ),
        rules,
      );
      expect(ids(result), {
        'closedSelfDraw',
        'singleWait',
        'seatFlower',
        'kongWin',
      });
      expect(result.score, 6);
      expect(ids(result), isNot(contains('noFlowers')));
    });
    test('all exposed replaces single wait on discard only', () {
      final melds = [
        Meld(MeldKind.chow, [0, 1, 2]),
        Meld(MeldKind.chow, [3, 4, 5]),
        Meld(MeldKind.chow, [9, 10, 11]),
        Meld(MeldKind.chow, [12, 13, 14]),
        Meld(MeldKind.chow, [18, 19, 20]),
      ];
      final result = scoreHand(hand('55s', melds: melds), rules);
      expect(ids(result), {'allExposed'});
      expect(result.score, 2);
      final drawn = scoreHand(
        hand('55s', melds: melds, source: WinSource.selfDraw),
        rules,
      );
      expect(ids(drawn), {'selfDraw', 'singleWait'});
    });
    test(
      'all honors and winds use explicitly documented additive house scores',
      () {
        final result = scoreHand(hand('11122233344455566z'), rules);
        expect(
          ids(result),
          containsAll(['allHonors', 'bigWinds', 'allPungs', 'fiveConcealed']),
        );
        expect(
          result.patterns.singleWhere((p) => p.id == 'allHonors').value,
          16,
        );
        expect(
          result.patterns.singleWhere((p) => p.id == 'bigWinds').value,
          16,
        );
      },
    );
  });
  group('reject invalid state and refuse unsupported history', () {
    test('incomplete, unknown context and invalid winning tile', () {
      expect(scoreHand(Hand(), Rules()).status, ResultStatus.incomplete);
      final tiles = parseTiles('123456789m123p55s');
      expect(
        scoreHand(Hand(concealed: tiles), Rules()).status,
        ResultStatus.needsContext,
      );
      expect(
        scoreHand(
          Hand(concealed: tiles, winningTile: 22, source: WinSource.selfDraw),
          Rules(),
        ).status,
        ResultStatus.needsContext,
      );
      expect(
        scoreHand(Hand(concealed: tiles, winningTile: 33), Rules()).status,
        ResultStatus.invalid,
      );
      expect(
        hk(hand('123456789m123p55s', winner: 4)).status,
        ResultStatus.invalid,
      );
    });
    test('meld validity and combined physical tile budget', () {
      for (final meld in [
        Meld(MeldKind.chow, [7, 8, 9]),
        Meld(MeldKind.chow, [27, 28, 29]),
        Meld(MeldKind.pung, [0, 0, 1]),
        Meld(MeldKind.closedKong, [0, 0, 0]),
        Meld(MeldKind.chow, [34, 35, 36]),
        Meld(MeldKind.pung, []),
      ]) {
        expect(
          hk(hand('123m456p789s22z', melds: [meld])).status,
          ResultStatus.invalid,
        );
      }
      expect(
        hk(
          hand(
            '123m456p789s22z',
            melds: [
              Meld(MeldKind.closedKong, [0, 0, 0, 0]),
            ],
          ),
        ).status,
        ResultStatus.invalid,
      );
      expect(hk(hand('11111m123p123s111z')).status, ResultStatus.invalid);
      expect(
        hk(
          hand(
            '123m456p789s22z',
            source: WinSource.selfDraw,
            melds: [
              Meld(MeldKind.chow, [2, 0, 1]),
            ],
          ),
        ).status,
        ResultStatus.valid,
      );
    });
    test(
      'flower duplicates, disabled flowers and seven/eight-flower declarations',
      () {
        expect(
          hk(hand('123456789m123p55s', flowers: [34, 34])).status,
          ResultStatus.invalid,
        );
        expect(
          hk(
            hand('123456789m123p55s', flowers: [34]),
            Rules(flowers: false),
          ).status,
          ResultStatus.invalid,
        );
        for (final count in [7, 8]) {
          final result = hk(
            hand(
              '123456789m123p55s',
              flowers: List.generate(count, (i) => 34 + i),
            ),
          );
          expect(result.status, ResultStatus.needsContext);
          expect(result.transfers, isEmpty);
        }
      },
    );
    test('event contradictions and invalid responsibility are blocked', () {
      final invalid = [
        hand('123456789m123p55s', lastTile: LastTile.draw),
        hand(
          '123456789m123p55s',
          source: WinSource.selfDraw,
          lastTile: LastTile.discard,
        ),
        hand(
          '123456789m123p55s',
          replacement: Replacement.flower,
          flowers: [34],
        ),
        hand(
          '123456789m123p55s',
          source: WinSource.selfDraw,
          replacement: Replacement.kong,
        ),
        hand('123456789m123p55s', source: WinSource.selfDraw, kongChain: 1),
        hand('123456789m123p55s', liablePlayer: 1),
        hand('123456789m123p55s', continuations: -1),
        hand('123456789m123p55s', discarder: 1),
      ];
      for (final h in invalid) {
        expect(hk(h).status, ResultStatus.invalid);
      }
      expect(
        scoreHand(
          hand('123456789m123456p55s', liablePlayer: 2),
          Rules.taiwanese(),
        ).status,
        ResultStatus.invalid,
      );
    });
    test('invalid rule bounds and override keys have no payment', () {
      for (final rules in [
        Rules(minimum: 2),
        Rules(cap: 11),
        Rules(minimum: 11),
        Rules(unit: 0),
        Rules(base: -1),
        Rules(overrides: {'imaginary': 2}),
        Rules(overrides: {'chows': 101}),
        Rules(overrides: {'chows': -1}),
        Rules.taiwanese().copyWith(cap: 0),
        Rules.taiwanese().copyWith(cap: 1001),
      ]) {
        expect(
          scoreHand(hand('123456789m123p55s'), rules).status,
          ResultStatus.invalid,
        );
      }
    });
    test('editable patterns match family, defaults, and enabled flowers', () {
      expect(defaultPatternValues(Rules())['bigDragons'], 5);
      expect(defaultPatternValues(Rules.taiwanese())['bigDragons'], 8);
      expect(defaultPatternValues(Rules()).containsKey('allHonors'), isFalse);
      expect(defaultPatternValues(Rules.taiwanese())['allHonors'], 16);
      expect(defaultPatternValues(Rules()).containsKey('closed'), isFalse);
      expect(defaultPatternValues(Rules(flowers: false))['closed'], 1);
      expect(validateRules(Rules(overrides: {'fiveConcealed': 8})), isNotEmpty);
      expect(
        validateRules(Rules(flowers: false, overrides: {'seatFlower': 1})),
        isNotEmpty,
      );
      expect(
        validateRules(Rules.taiwanese().copyWith(overrides: {'allHonors': 8})),
        isEmpty,
      );
      expect(Rules.taiwanese().copyWith(cap: 8).custom, isTrue);
      expect(Rules.taiwanese().copyWith(flowers: false).custom, isTrue);
    });
    test('hand and rules are immutable, JSON compatible and deterministic', () {
      final original = hand('123456789m123p55s', source: WinSource.selfDraw);
      final copy = Hand.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(copy.toJson(), original.toJson());
      final rules = Rules(overrides: {'chows': 2});
      expect(
        Rules.fromJson(jsonDecode(jsonEncode(rules.toJson()))).toJson(),
        rules.toJson(),
      );
      expect(() => copy.concealed.add(0), throwsUnsupportedError);
      expect(() => rules.overrides['chows'] = 3, throwsUnsupportedError);
      expect(hk(copy, rules).score, hk(original, rules).score);
    });
  });
  test('additional source boundaries and saved kong round trip', () {
    final smallWinds = scoreHand(
      hand('111222333z456m789p44z'),
      Rules.taiwanese(),
    );
    expect(
      smallWinds.patterns.singleWhere((p) => p.id == 'smallWinds').value,
      8,
    );
    expect(ids(smallWinds), isNot(contains('bigWinds')));
    expect(hk(hand('123456789m123p56s')).status, ResultStatus.invalid);
    final invalid = [
      hand(
        '123456789m123p55s',
        source: WinSource.selfDraw,
        replacement: Replacement.flower,
      ),
      hand('123456789m123p55s', earthly: true, discarder: 3),
      hand('123456789m123p55s', heavenly: true, earthly: true),
      hand(
        '123456789m123p55s',
        source: WinSource.selfDraw,
        winner: 0,
        heavenly: true,
        lastTile: LastTile.draw,
      ),
    ];
    for (final h in invalid) {
      expect(hk(h).status, ResultStatus.invalid);
    }
    expect(
      scoreHand(
        hand(
          '123456789m123456p55s',
          source: WinSource.selfDraw,
          winner: 0,
          heavenly: true,
        ),
        Rules.taiwanese(),
      ).status,
      ResultStatus.invalid,
    );
    final original = hand(
      '123m456p789s22z',
      source: WinSource.selfDraw,
      melds: [
        Meld(MeldKind.closedKong, [31, 31, 31, 31]),
      ],
      replacement: Replacement.kong,
      kongChain: 1,
    );
    final restored = Hand.fromJson(jsonDecode(jsonEncode(original.toJson())));
    expect(restored.toJson(), original.toJson());
    expect(
      hk(restored).patterns.map((p) => p.id),
      hk(original).patterns.map((p) => p.id),
    );
    expect(
      hk(restored).transfers.map((t) => t.toJson()),
      hk(original).transfers.map((t) => t.toJson()),
    );
  });
  test(
    '1000 generated hands preserve score under tile order and suit rotation',
    () {
      final random = Random(240213);
      int rotate(int t) => t < 27 ? (t + 9) % 27 : t;
      for (var i = 0; i < 1000; i++) {
        final rules = i.isEven ? Rules() : Rules.taiwanese();
        final tiles = generatedWin(random, rules.groupCount);
        final h = Hand(
          concealed: tiles,
          winningTile: tiles.last,
          source: WinSource.selfDraw,
          winner: 1,
          dealer: 0,
          roundWind: 2,
          circumstancesConfirmed: true,
        );
        final first = scoreHand(h, rules);
        tiles.shuffle(random);
        final shuffled = Hand(
          concealed: tiles,
          winningTile: h.winningTile,
          source: h.source,
          winner: 1,
          dealer: 0,
          roundWind: 2,
          circumstancesConfirmed: true,
        );
        final changed = Hand(
          concealed: tiles.map(rotate),
          winningTile: rotate(h.winningTile!),
          source: h.source,
          winner: 1,
          dealer: 0,
          roundWind: 2,
          circumstancesConfirmed: true,
        );
        for (final other in [
          scoreHand(shuffled, rules),
          scoreHand(changed, rules),
        ]) {
          expect(other.status, first.status, reason: 'generated case $i');
          expect(other.rawScore, first.rawScore, reason: 'generated case $i');
          expect(other.balances, first.balances);
        }
        expect(first.balances.reduce((a, b) => a + b), 0);
      }
    },
  );
}
