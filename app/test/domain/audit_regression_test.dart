import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/domain/scoring.dart';
import 'package:mahjong_vision/domain/tiles.dart';

import 'scoring_test.dart' show hand, ids;

void main() {
  test(
    '108 non-monotonic custom tier and cap combinations use best legal role',
    () {
      final h = hand('123333m555p777s11122z', win: 2);
      for (final three in [0, 1, 2, 5, 20, 100]) {
        for (final four in [0, 1, 2, 5, 20, 100]) {
          for (final cap in [1, 5, 100]) {
            final rules = Rules.taiwanese().copyWith(
              cap: cap,
              overrides: {'threeConcealed': three, 'fourConcealed': four},
            );
            final result = scoreHand(h, rules);
            final expected = 1 + (three > four ? three : four);
            expect(
              result.rawScore,
              expected,
              reason: 'three=$three, four=$four, cap=$cap',
            );
            expect(result.score, expected > cap ? cap : expected);
            expect(result.total, 50 + 10 * result.score);
            expect(result.balances.reduce((a, b) => a + b), 0);
          }
        }
      }
    },
  );

  test(
    'custom tai values maximize winning-tile allocation, not hidden count',
    () {
      // The winning 3m can complete either 123m or 333m. The other groups are
      // 555p, 777s, 111z and eye 22z. Both interpretations are legal.
      final h = hand('123333m555p777s11122z', win: 2);
      final defaults = scoreHand(h, Rules.taiwanese());
      expect(ids(defaults), contains('fourConcealed'));
      expect(
        defaults.score,
        6,
      ); // closed 1 + four concealed 5; also waits for 2z
      final custom = scoreHand(
        h,
        Rules.taiwanese().copyWith(
          overrides: {'threeConcealed': 20, 'fourConcealed': 0},
        ),
      );
      expect(custom.status, ResultStatus.valid);
      expect(ids(custom), contains('threeConcealed'));
      expect(ids(custom), isNot(contains('fourConcealed')));
      expect(custom.score, 21);
      expect(custom.total, 260); // nondealer discard: 50 + 21 * 10
      // A self-drawn tile cannot choose to become a discard-completed pung.
      final drawn = Hand.fromJson({
        ...h.toJson(),
        'source': WinSource.selfDraw.name,
      });
      final self = scoreHand(
        drawn,
        Rules.taiwanese().copyWith(
          overrides: {'threeConcealed': 20, 'fourConcealed': 0},
        ),
      );
      expect(ids(self), isNot(contains('threeConcealed')));
      expect(self.score, 3); // closed self draw 3; also waits for 2z
    },
  );

  test('two discard-fed kongs cannot be a consecutive replacement chain', () {
    final melds = [
      for (final t in [31, 32]) Meld(MeldKind.openKong, [t, t, t, t]),
    ];
    final h = hand(
      '123m456p55s',
      source: WinSource.selfDraw,
      melds: melds,
      replacement: Replacement.kong,
      kongChain: 2,
    );
    expect(scoreHand(h, Rules()).status, ResultStatus.invalid);
    final one = Hand.fromJson({...h.toJson(), 'kongChain': 1});
    expect(scoreHand(one, Rules()).status, ResultStatus.valid);
    for (final kind in [MeldKind.closedKong, MeldKind.addedKong]) {
      final possible = Hand.fromJson({
        ...h.toJson(),
        'melds': [
          melds.first.toJson(),
          Meld(kind, [32, 32, 32, 32]).toJson(),
        ],
      });
      expect(ids(scoreHand(possible, Rules())), {'doubleKongWin'});
    }
  });

  test(
    'HK responsibility requires a possible declared liability structure',
    () {
      final plain = hand(
        '123456789m123p55s',
        source: WinSource.selfDraw,
        liablePlayer: 2,
      );
      expect(scoreHand(plain, Rules()).status, ResultStatus.invalid);
      final fourClosed = hand(
        '55s',
        source: WinSource.selfDraw,
        liablePlayer: 2,
        melds: [
          for (final t in [0, 9, 18, 31])
            Meld(MeldKind.closedKong, [t, t, t, t]),
        ],
      );
      expect(scoreHand(fourClosed, Rules()).status, ResultStatus.invalid);
      final four = hand(
        '55s',
        source: WinSource.selfDraw,
        liablePlayer: 2,
        melds: [
          for (final t in [0, 9, 18, 31]) Meld(MeldKind.pung, [t, t, t]),
        ],
      );
      final payable = scoreHand(four, Rules());
      expect(payable.status, ResultStatus.valid);
      expect(payable.transfers.single.from, 2);
      final dragons = hand(
        '123m22p',
        source: WinSource.selfDraw,
        liablePlayer: 2,
        melds: [
          for (final t in [31, 32, 33]) Meld(MeldKind.pung, [t, t, t]),
        ],
      );
      expect(scoreHand(dragons, Rules()).status, ResultStatus.valid);
      final concealedDragons = hand(
        '123m22p',
        source: WinSource.selfDraw,
        liablePlayer: 2,
        melds: [
          for (final t in [31, 32, 33]) Meld(MeldKind.closedKong, [t, t, t, t]),
        ],
      );
      expect(scoreHand(concealedDragons, Rules()).status, ResultStatus.invalid);
    },
  );

  test(
    'HK initial dealing includes flower replacement before heavenly win',
    () {
      final h = hand(
        '123456789m123p55s',
        winner: 0,
        source: WinSource.selfDraw,
        flowers: [34],
        replacement: Replacement.flower,
        heavenly: true,
      );
      final result = scoreHand(h, Rules());
      expect(result.status, ResultStatus.valid);
      expect(ids(result), {'heavenly'});
      expect(result.score, 10);
      final kong = hand(
        '123m456p789s22z',
        winner: 0,
        source: WinSource.selfDraw,
        melds: [
          Meld(MeldKind.closedKong, [31, 31, 31, 31]),
        ],
        replacement: Replacement.kong,
        kongChain: 1,
        heavenly: true,
      );
      expect(scoreHand(kong, Rules()).status, ResultStatus.invalid);
    },
  );
}
