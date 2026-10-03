import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/domain/scoring.dart';
import 'package:mahjong_vision/domain/tiles.dart';

import 'scoring_test.dart' show hand;
import 'settlement_test.dart' show conserved, paid;

void main() {
  // HKMA Chinese 香港麻雀總例, 簡則 14: direct kong-replacement
  // self-draw is exempt from responsibility. The literal source payout rows
  // below are independent of scoring.dart's exported conversion table.
  test('576 HK kong-replacement settlements waive declared responsibility', () {
    const rows = [
      (3, 32, 16),
      (4, 64, 32),
      (5, 96, 48),
      (6, 128, 64),
      (7, 192, 96),
      (8, 256, 128),
      (9, 384, 192),
      (10, 512, 256),
    ];
    var cases = 0;
    for (final row in rows) {
      for (var winner = 0; winner < 4; winner++) {
        for (var liable = 0; liable < 4; liable++) {
          if (liable == winner) continue;
          for (final mode in PaymentMode.values) {
            for (final unit in [1, 7]) {
              final total = row.$2 * unit;
              final expected = <int, int>{};
              for (var position = 1; position <= 3; position++) {
                expected[(winner + position) % 4] = switch (mode) {
                  PaymentMode.preset => row.$3 * unit,
                  PaymentMode.fullEach => total,
                  PaymentMode.splitTotal =>
                    total ~/ 3 + (position <= total % 3 ? 1 : 0),
                };
              }
              final result = settle(
                Hand(
                  winner: winner,
                  source: WinSource.selfDraw,
                  replacement: Replacement.kong,
                  liablePlayer: liable,
                ),
                Rules(payment: mode, unit: unit),
                row.$1,
              );
              expect(paid(result), expected);
              expect(result.map((t) => t.reason).toSet(), {'自摸'});
              conserved(result, winner);
              cases++;
            }
          }
        }
      }
    }
    expect(cases, 576);
  });

  Hand declaredHand({
    Replacement replacement = Replacement.none,
    List<int> flowers = const [],
  }) => hand(
    '55s',
    source: WinSource.selfDraw,
    replacement: replacement,
    kongChain: replacement == Replacement.kong ? 1 : 0,
    flowers: flowers,
    liablePlayer: 3,
    melds: [
      Meld(MeldKind.pung, parseTiles('111m')),
      Meld(MeldKind.pung, parseTiles('222p')),
      Meld(MeldKind.pung, parseTiles('333s')),
      Meld(MeldKind.addedKong, parseTiles('5555z')),
    ],
  );

  test('complete 7-faan replacement hand pays three opponents, not bao', () {
    final h = declaredHand(replacement: Replacement.kong);
    const expected = {
      PaymentMode.preset: {0: 96, 2: 96, 3: 96},
      PaymentMode.fullEach: {0: 192, 2: 192, 3: 192},
      PaymentMode.splitTotal: {0: 64, 2: 64, 3: 64},
    };
    for (final entry in expected.entries) {
      final result = scoreHand(h, Rules(payment: entry.key));
      expect(result.status, ResultStatus.valid);
      expect(result.score, 7);
      expect(paid(result.transfers), entry.value);
      expect(result.transfers.map((t) => t.reason).toSet(), {'自摸'});
    }
  });

  test(
    'ordinary and flower-replacement self-draw retain prior responsibility',
    () {
      // Having an earlier kong is not itself an exemption. Only a win directly
      // on its replacement is; drawing a flower resets that kong-win context.
      for (final fixture in [
        (declaredHand(), 6, [192, 384, 128]),
        (
          declaredHand(replacement: Replacement.flower, flowers: [34]),
          5,
          [144, 288, 96],
        ),
      ]) {
        for (final mode in PaymentMode.values) {
          final result = scoreHand(fixture.$1, Rules(payment: mode));
          expect(result.status, ResultStatus.valid);
          expect(result.score, fixture.$2);
          expect(paid(result.transfers), {3: fixture.$3[mode.index]});
          expect(result.transfers.single.reason, '包牌');
        }
      }
    },
  );

  test('rob-added-kong retains kong-player full self-draw total', () {
    final h = hand(
      '123m456p77s',
      win: 0,
      source: WinSource.robAddedKong,
      liablePlayer: 3,
      melds: [
        Meld(MeldKind.pung, parseTiles('555z')),
        Meld(MeldKind.pung, parseTiles('666z')),
      ],
    );
    const expected = [96, 192, 64];
    for (final mode in PaymentMode.values) {
      final result = scoreHand(h, Rules(payment: mode));
      expect(result.status, ResultStatus.valid);
      expect(result.score, 4);
      expect(paid(result.transfers), {2: expected[mode.index]});
      expect(result.transfers.single.reason, '搶槓結算');
    }
  });

  test('thirteen-orphans rob-concealed-kong retains robbed-player payment', () {
    final h = hand(
      '19m19p19s11234567z',
      win: 0,
      source: WinSource.robConcealedKong,
      liablePlayer: 3,
    );
    const expected = [768, 1536, 512];
    for (final mode in PaymentMode.values) {
      final result = scoreHand(h, Rules(payment: mode));
      expect(result.status, ResultStatus.valid);
      expect(result.score, 10);
      expect(paid(result.transfers), {2: expected[mode.index]});
      expect(result.transfers.single.reason, '搶槓結算');
    }
  });
}
