# What is ready, and what still needs work

Domain verification and readiness review: 2026-10-03; engine 0.1.2; app testing-build version remains 0.3.0+3. **Vision is not the only remaining work.** The app has two executable rule packs with tested scoring and payment paths. The original broad goal covers many more rule families and game-history events than those two packs implement. Neither a code-coverage percentage nor a vision accuracy percentage measures completion of that broader goal.

| Area | Current state |
| --- | --- |
| Hong Kong 13-tile hand calculator | Implements the adopted HKMA Chinese ordinary scoring catalogue, non-flower limit hands, 3–10-faan payment table and supported payment overrides. It requires accurate manual context and excludes instant flower wins. Engine 0.1.2 corrects the direct kong-replacement responsibility exception described below. |
| Taiwanese 16-tile hand calculator | Implements the explicitly documented **partial house preset**, including selected tai patterns, exclusions, five-group decomposition and base-plus-tai payments. It is neither a national standard nor a complete Gametower preset. |
| Other researched families | **Not implemented.** HK-style modern 16-tile, Riichi four/three-player, MCR, Zung Jung, Singapore, Sichuan blood battle/blood flow, Guangdong pushdown/chicken/new styles, Malaysian three-player and American rules remain research/specification work. |
| Custom preferences | Supported ordinary pattern values, minimum/cap, flowers, base/unit and supported self-draw payment policies work within their documented constraints. Arbitrary new shapes, alternative exclusions, payer policies and history rules cannot be created merely by editing a number. |
| Game-history adjudication | Not complete: passed-win eligibility, event timing, supplier/order-based responsibility, claim priority/multiple winners, flow of dealer/round/continuations, penalties and side transactions need more state than a final hand photo supplies. |
| Session accounting | Saved-hand transfers are snapshots, not a complete mahjong game/event ledger. Automatic game progression, draw settlement, deposits, carry-over debts, kong/flower immediate payments and refunds remain separate work. |

The adopted HK reference is the [HKMA 香港麻雀總例](https://docs.google.com/document/d/1TgdYpE_5Qiht_lBco3BqN_ijZJDRWugwzRzv946raq0/edit), linked from the association's [rules index](https://www.hkmahjong.org/rules). The index distinguishes Hong Kong mahjong from Hong Kong-style modern 16-tile mahjong. They are not interchangeable presets. Taiwan definitions were compared with the [Gametower publisher's table](https://www.gametower.com.tw/Games/Freeplay/MJ/Star31/Data/i_ingame-count.aspx); that source has its own platform options and different ambiguous-hand treatment. The app's precise house choices are in [SCORING_IMPLEMENTATION.md](SCORING_IMPLEMENTATION.md).

## What the tests establish

The domain suite checks physical tile bounds, legal structures, original scoring examples, every row of the adopted HK conversion table, dealer/payer formulas, responsibility arithmetic, caps, rounding and incompatible inputs. It includes:

- 6,000 seeded structural cases compared with an independent sequence-transfer oracle: 1,000 constructed wins, 1,000 single-tile mutations, and 4,000 unconstrained cases, over zero to five groups. This is sampled verification, not enumeration of every possible mahjong hand.
- 1,000 generated winning hands checked for score/payment invariance under tile reordering and suit rotation. These invariants cannot prove that the underlying regional scoring definitions are correct.
- 4,608 HK payment combinations using literal source-table expected values; 1,152 additional custom rob-kong combinations; and 3,840 Taiwan formula combinations. The Taiwan expectations verify the documented house contract, not a universal Taiwanese standard.
- Original positive and negative pattern examples, including four new audit counterexamples, plus 108 custom-tier/cap combinations. A custom minimum in the Taiwan house pack refers to hand tai before per-payer dealer additions.
- Five further 0.1.2 tests include 576 direct kong-replacement payment combinations, a complete-hand counterexample and preservation checks for ordinary/flower-replacement responsibility and both robbed-kong branches.

The audit found real bugs despite the previous high line-coverage result: the engine could choose the wrong winning-tile role under non-monotonic custom tai values; it admitted impossible consecutive open-kong chains and structurally impossible HK responsibility; and it rejected a heavenly win completed by flower replacement during initial dealing. These have regression tests and fixes. This is why passing tests or high line coverage must not be described as “all mahjong logic is finished.”

Verification on 2026-10-03: **76 named domain tests pass**, including the loops above; domain static analysis is clean; the full Flutter application suite passes **206 tests**. No native build was produced by this rules audit. The historical 0.1.1 combined 196-test application coverage run executed 499/501 scoring lines and 71/71 tile lines (the domain-only audit executed 496/501 scoring lines). Those coverage figures are not a new measurement of engine 0.1.2; packaged artifact verification is reported separately in [BUILD_VALIDATION.md](BUILD_VALIDATION.md). Executed lines do not measure rule completeness, all branch combinations or independent rules certification.

## Source-conformance correction from the readiness review

**Hong Kong kong-replacement responsibility:** a fresh download of the Chinese HKMA source confirms that summary rule 14 exempts direct kong-replacement self-draw from responsibility. Engine 0.1.1 incorrectly consolidated these payments into the declared responsible player. Engine 0.1.2 uses the selected three-payer self-draw policy for `Replacement.kong`. Ordinary or flower-replacement self-draw responsibility and robbed-kong payments retain their documented behavior. Historical saved transfers are preserved; recalculating a draft uses the new engine.

For example, declared groups `111m`, `222p`, `333s`, `5555z` (added kong), concealed `55s`, a direct kong-replacement self-draw, no flowers, one declared responsible opponent and the default rules produce seven faan. The new regression test observed the incorrect charge of 288 before the fix and now verifies 96 from each opponent. This was missed by the earlier high-coverage suite. The Chinese detailed payment paragraph and linked English edition do not repeat the explicit exception; the pack follows the Chinese summary clause, not an assumption that both editions are identical. See [the precise scope and source recheck](SCORING_IMPLEMENTATION.md#hong-kong-pack-hk-hand-2025).

## Deliberate exclusions still present in the two packs

**Both packs:** seven/eight-flower holdings block automatic settlement because instant declaration/waiver history is not represented. The app cannot prove that an asserted win is timely or that a player has not passed a win. Winning source, winning tile, meld exposure, winds, dealer and relevant special events remain player inputs.

**Hong Kong:** structural bao validation only proves that liability could exist. Who supplied the decisive group, whether it was last, and which applicable liability occurred later still require accurate user confirmation. Heavenly/earthly timing and preceding actions are not reconstructed. Flower wins, penalties, simultaneous-claim priority and full round progression remain unimplemented.

**Taiwan house preset:** heavenly/earthly flags, declared responsibility and concealed-kong robbery are rejected. Ready/early-ready, publisher-specific bonuses and unlisted special hands are not implemented; they are not available through a manual declaration switch. Alternative all-honor/flower conventions and other households' stacking rules require a reviewed definition change. The adopted all-honors value, numbered-flower mapping, closed-kong treatment and stacking policies are explicit house choices. Single-wait scoring uses this player's structural waits, without public-discard availability; minimum eligibility uses hand tai before dealer additions. These are documented contract choices, not universal Taiwan rules. A user who plays different definitions needs an additional reviewed preset, not just an assumption that “台牌” matches.

No additional ban on last-wall-tile plus replacement has been invented: the adopted HK rules permit tail replacement from the wall and do not specify a blanket exclusion. Further variants can define that relationship separately.

## Work needed before broader rule claims

1. Finish a sourced, versioned executable specification for each additional family, including eligibility, exclusions, payments, rounding and event-dependent rules; reconcile conflicting local conventions as separate presets.
2. Add an event model and corresponding user controls for the history-dependent cases instead of asking a photo classifier to infer them.
3. Obtain independent review of the two current packs from experienced players against the selected references and explicit house contract, with published positive/negative examples.
4. Extend integration and saved-rule migration tests whenever rules or settings change; preserve prior saved transfers instead of silently recalculating them.
5. Continue physical-device testing, distribution/build checks and vision validation independently. A successful Xcode build or scan does not certify the rule catalogue.

The current app can be used to test its stated scope. It should not be presented as a complete universal mahjong adjudicator or as having only vision work left.
