import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/domain/scoring.dart';

Hand context({
  int winner = 1,
  int dealer = 0,
  int discarder = 2,
  WinSource source = WinSource.discard,
  int repeat = 0,
  int? liable,
}) => Hand(
  winner: winner,
  dealer: dealer,
  discarder: discarder,
  source: source,
  continuations: repeat,
  liablePlayer: liable,
);

Map<int, int> paid(List<Transfer> transfers) => {
  for (final transfer in transfers) transfer.from: transfer.amount,
};

void conserved(List<Transfer> transfers, int winner) {
  expect(
    transfers.every((t) => t.to == winner && t.from != winner && t.amount >= 0),
    isTrue,
  );
  expect(transfers.map((t) => t.from).toSet().length, transfers.length);
  final balances = ScoreResult(
    ResultStatus.valid,
    transfers: transfers,
  ).balances;
  expect(balances.fold<int>(0, (a, b) => a + b), 0);
  expect(balances[winner], transfers.fold<int>(0, (a, b) => a + b.amount));
}

void main() {
  group('HKMA complete conversion table', () {
    // Transcribed from HKMA 2025 final conversion table; independent of the
    // implementation's exported table. Unit=1 means abstract source points.
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
    for (final row in rows) {
      test('${row.$1} faan: every seat, dealer, discarder and scale', () {
        for (var winner = 0; winner < 4; winner++) {
          for (var dealer = 0; dealer < 4; dealer++) {
            for (var discarder = 0; discarder < 4; discarder++) {
              if (discarder == winner) continue;
              for (final unit in [1, 7, 1000000]) {
                final rules = Rules(unit: unit);
                final ron = settle(
                  context(winner: winner, dealer: dealer, discarder: discarder),
                  rules,
                  row.$1,
                );
                expect(paid(ron), {discarder: row.$2 * unit});
                conserved(ron, winner);
                final draw = settle(
                  context(
                    winner: winner,
                    dealer: dealer,
                    discarder: discarder,
                    source: WinSource.selfDraw,
                  ),
                  rules,
                  row.$1,
                );
                expect(paid(draw), {
                  for (var p = 0; p < 4; p++)
                    if (p != winner) p: row.$3 * unit,
                });
                conserved(draw, winner);
                for (final source in [
                  WinSource.robAddedKong,
                  WinSource.robConcealedKong,
                ]) {
                  final rob = settle(
                    context(
                      winner: winner,
                      dealer: dealer,
                      discarder: discarder,
                      source: source,
                      liable: (discarder + 1) % 4 == winner
                          ? discarder
                          : (discarder + 1) % 4,
                    ),
                    rules,
                    row.$1,
                  );
                  expect(paid(rob), {discarder: row.$3 * 3 * unit});
                  conserved(rob, winner);
                }
              }
            }
          }
        }
      });
    }
    test('responsibility consolidates self draw, never ordinary discard', () {
      expect(
        paid(
          settle(context(source: WinSource.selfDraw, liable: 3), Rules(), 3),
        ),
        {3: 48},
      );
      expect(paid(settle(context(liable: 3), Rules(), 3)), {2: 32});
      expect(
        paid(
          settle(
            context(source: WinSource.robAddedKong, liable: 3),
            Rules(),
            3,
          ),
        ),
        {2: 48},
      );
    });
    test('custom each-full and fixed-total have distinct meanings', () {
      final h = context(source: WinSource.selfDraw, winner: 3);
      expect(paid(settle(h, Rules(payment: PaymentMode.fullEach), 3)), {
        0: 32,
        1: 32,
        2: 32,
      });
      // Winner 3 -> first and second clockwise payers absorb the remainder.
      expect(paid(settle(h, Rules(payment: PaymentMode.splitTotal), 3)), {
        0: 11,
        1: 11,
        2: 10,
      });
      expect(
        paid(
          settle(
            context(source: WinSource.selfDraw, winner: 2),
            Rules(payment: PaymentMode.splitTotal),
            4,
          ),
        ),
        {3: 22, 0: 21, 1: 21},
      );
    });
    test(
      'rob kong follows selected self-draw policy and replaces responsibility',
      () {
        // Direct boundary examples: all three supported methods must differ.
        for (final example in [
          (PaymentMode.preset, 48),
          (PaymentMode.fullEach, 96),
          (PaymentMode.splitTotal, 32),
        ]) {
          expect(
            paid(
              settle(
                context(source: WinSource.robAddedKong, liable: 3),
                Rules(payment: example.$1),
                3,
              ),
            ),
            {2: example.$2},
          );
        }
        // All source-table rows, payer positions, policies and scaling factors.
        for (final row in rows) {
          for (final mode in PaymentMode.values) {
            for (var winner = 0; winner < 4; winner++) {
              for (var discarder = 0; discarder < 4; discarder++) {
                if (winner == discarder) continue;
                final liable = List.generate(
                  4,
                  (i) => i,
                ).firstWhere((p) => p != winner && p != discarder);
                for (final unit in [1, 7]) {
                  final expected =
                      unit *
                      (mode == PaymentMode.preset
                          ? row.$3 * 3
                          : mode == PaymentMode.fullEach
                          ? row.$2 * 3
                          : row.$2);
                  for (final source in [
                    WinSource.robAddedKong,
                    WinSource.robConcealedKong,
                  ]) {
                    final transfers = settle(
                      context(
                        winner: winner,
                        discarder: discarder,
                        source: source,
                        liable: liable,
                      ),
                      Rules(payment: mode, unit: unit),
                      row.$1,
                    );
                    expect(paid(transfers), {discarder: expected});
                    expect(transfers.single.reason, '搶槓結算');
                    conserved(transfers, winner);
                  }
                }
              }
            }
          }
        }
      },
    );
    test(
      'every table row/custom method/seat conserves and rotates remainders',
      () {
        for (final row in rows) {
          for (final mode in PaymentMode.values) {
            for (var winner = 0; winner < 4; winner++) {
              final transfers = settle(
                context(winner: winner, source: WinSource.selfDraw),
                Rules(payment: mode),
                row.$1,
              );
              conserved(transfers, winner);
              final total = transfers.fold<int>(0, (a, b) => a + b.amount);
              expect(
                total,
                mode == PaymentMode.splitTotal
                    ? row.$2
                    : mode == PaymentMode.fullEach
                    ? row.$2 * 3
                    : row.$3 * 3,
              );
              if (mode == PaymentMode.splitTotal) {
                final amounts = paid(transfers);
                expect(
                  amounts[(winner + 1) % 4]! - amounts[(winner + 3) % 4]!,
                  lessThanOrEqualTo(1),
                );
              }
            }
          }
        }
      },
    );
  });
  group('Taiwan house base plus tai contract', () {
    final rules = Rules.taiwanese();
    test('50 base, 10/tai, 6 hand tai: different dealer payer', () {
      expect(paid(settle(context(), rules, 6)), {2: 110});
      expect(paid(settle(context(discarder: 0), rules, 6)), {0: 120});
      expect(paid(settle(context(winner: 0, discarder: 2), rules, 6)), {
        2: 120,
      });
      expect(paid(settle(context(source: WinSource.selfDraw), rules, 6)), {
        0: 120,
        2: 110,
        3: 110,
      });
      expect(
        paid(settle(context(source: WinSource.selfDraw, winner: 0), rules, 6)),
        {1: 120, 2: 120, 3: 120},
      );
    });
    test('repeat 1 and 2 use total dealer additions 3 and 5', () {
      expect(
        paid(settle(context(source: WinSource.selfDraw, repeat: 1), rules, 6)),
        {0: 140, 2: 110, 3: 110},
      );
      expect(
        paid(settle(context(source: WinSource.selfDraw, repeat: 2), rules, 6)),
        {0: 160, 2: 110, 3: 110},
      );
      expect(paid(settle(context(winner: 0, repeat: 2), rules, 6)), {2: 160});
      expect(paid(settle(context(repeat: 2), rules, 6)), {2: 110});
    });
    test('cap is applied to hand plus dealer additions per payer', () {
      expect(
        paid(
          settle(
            context(source: WinSource.selfDraw, repeat: 2),
            rules.copyWith(cap: 7),
            6,
          ),
        ),
        {0: 120, 2: 110, 3: 110},
      );
      expect(
        paid(
          settle(context(winner: 0, repeat: 100), rules.copyWith(cap: 7), 7),
        ),
        {2: 120},
      );
    });
    test(
      'zero tai legal, base zero legal, maximum permitted arithmetic exact',
      () {
        expect(paid(settle(context(), rules, 0)), {2: 50});
        expect(paid(settle(context(), rules.copyWith(base: 0, unit: 1), 0)), {
          2: 0,
        });
        final max = rules.copyWith(base: 1000000, unit: 1000000, cap: 1000);
        expect(paid(settle(context(winner: 0, repeat: 100), max, 1000)), {
          2: 1001000000,
        });
      },
    );
    test(
      'robbed kong follows discard payment, including dealer relationship',
      () {
        expect(
          paid(settle(context(source: WinSource.robAddedKong), rules, 6)),
          {2: 110},
        );
        expect(
          paid(
            settle(
              context(source: WinSource.robAddedKong, discarder: 0),
              rules,
              6,
            ),
          ),
          {0: 120},
        );
      },
    );
    test('fixed total is an explicit house policy without payer weighting', () {
      final split = rules.copyWith(payment: PaymentMode.splitTotal);
      expect(paid(settle(context(source: WinSource.selfDraw), split, 6)), {
        2: 37,
        3: 37,
        0: 36,
      });
      expect(
        paid(settle(context(source: WinSource.selfDraw, winner: 0), split, 6)),
        {1: 40, 2: 40, 3: 40},
      );
      expect(
        paid(
          settle(
            context(source: WinSource.selfDraw, winner: 0, repeat: 2),
            split,
            6,
          ),
        ),
        {1: 54, 2: 53, 3: 53},
      );
    });
    test(
      '3840 payer permutations and boundary counters satisfy exact formula',
      () {
        var cases = 0;
        for (final score in [0, 1, 6, 99, 100]) {
          for (var winner = 0; winner < 4; winner++) {
            for (var dealer = 0; dealer < 4; dealer++) {
              for (var discarder = 0; discarder < 4; discarder++) {
                if (discarder == winner) continue;
                for (final repeat in [0, 1, 2, 100]) {
                  for (final source in [
                    WinSource.discard,
                    WinSource.selfDraw,
                    WinSource.robAddedKong,
                    WinSource.robConcealedKong,
                  ]) {
                    final transfers = settle(
                      context(
                        winner: winner,
                        dealer: dealer,
                        discarder: discarder,
                        repeat: repeat,
                        source: source,
                      ),
                      rules,
                      score,
                    );
                    conserved(transfers, winner);
                    for (final transfer in transfers) {
                      final adjusted =
                          score +
                          ((winner == dealer || transfer.from == dealer)
                              ? 1 + repeat * 2
                              : 0);
                      expect(
                        transfer.amount,
                        50 + 10 * (adjusted > 100 ? 100 : adjusted),
                      );
                    }
                    cases++;
                  }
                }
              }
            }
          }
        }
        expect(cases, 3840);
      },
    );
  });
  test('settlement rejects malformed inputs before producing transfers', () {
    for (final h in [
      Hand(),
      context(winner: -1),
      context(dealer: 4),
      context(discarder: 4),
      context(discarder: 1),
      context(liable: 1),
      context(liable: -1),
      context(repeat: 101),
    ]) {
      expect(() => settle(h, Rules(), 3), throwsArgumentError);
    }
    expect(() => settle(context(), Rules(), 2), throwsArgumentError);
    expect(() => settle(context(), Rules(), 11), throwsArgumentError);
    expect(() => settle(context(), Rules(unit: 0), 3), throwsArgumentError);
    expect(
      () => settle(context(liable: 2), Rules.taiwanese(), 3),
      throwsArgumentError,
    );
  });
}
