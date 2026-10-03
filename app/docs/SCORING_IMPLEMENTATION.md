# Scoring engine implementation contract

Edition: 2026-10-03; engine version 0.1.2. This is a testable alpha with two executable packs, not a claim to implement every regional rule. The broader catalogue remains in `RULESET_RESEARCH.md`. Rules calculate abstract points, not a currency. All examples below are original test hands or arithmetic fixtures. Version 0.1.1 fixed ambiguous winning-tile allocation under custom values, impossible kong chains and responsibility, and initial flower replacement with heavenly win. Version 0.1.2 fixes the adopted Chinese source's kong-replacement responsibility exception. Saved historical transfers remain unchanged; an explicitly reloaded/recalculated draft uses the new engine. The app testing-build version remains 0.3.0+3.

The app separates recognition, physical hand validation, legal decomposition, pattern scoring, and transfers between players. Vision never decides self draw, exposed/concealed history, responsibility, or the winning tile's role. A result requires the player to confirm circumstances. This confirmation is a declaration by the player, not proof from a photograph.

## Hong Kong pack: hk-hand-2025

Reference: [Hong Kong Mahjong Association, 香港麻雀總例 (2025)](https://docs.google.com/document/d/1TgdYpE_5Qiht_lBco3BqN_ijZJDRWugwzRzv946raq0/edit), scoring principles, pattern catalogue, liability and final conversion table. This implementation and its original explanatory text are not an official association product or endorsement.

Implemented: ordinary four-group-and-pair hands; thirteen orphans; all ordinary patterns from the referenced catalogue; the non-flower limit hands; additive ordinary scoring; highest legal decomposition; minimum three and cap ten. Limits score ten before an optional lower custom cap. The no-flower variant awards closed-hand only if there were no calls or kongs. Seat and round wind stack. Dragon groups stack with small/big dragons. Numbered flowers determine the seat match. Flower and kong replacement events differ.

| Faan | Discarder pays | Each opponent pays on self draw |
| --- | ---: | ---: |
| 3 | 32 | 16 |
| 4 | 64 | 32 |
| 5 | 96 | 48 |
| 6 | 128 | 64 |
| 7 | 192 | 96 |
| 8 | 256 | 128 |
| 9 | 384 | 192 |
| 10 | 512 | 256 |

Robbing a permitted kong awards its bonus, but is not a self-draw pattern; the kong player pays the entire self-draw total. This includes the selected custom payment policy: at three faan and unit one, the robbed player pays 48 under the preset, 96 under full-each, or 32 under split-total. Other responsibility is replaced by the kong player's liability. Declared responsibility consolidates self-draw payments and is ignored on an ordinary discard win. Self-draw responsibility requires a structurally possible twelve-tile or declared big-dragons liability: four declared groups, or all three declared dragon groups, with at least one relevant group fed by another player. The player must supply the last applicable responsible player; the alpha cannot infer liability from meld order or suppliers. Passing that structural check does not prove the declaration order made responsibility applicable.

**Direct kong-replacement exception:** the adopted Chinese source's summary rule 14 exempts direct kong-replacement self-draw from responsibility. With `Replacement.kong`, all three opponents pay according to the selected self-draw policy; a declared responsible player does not absorb the others' payments. Merely having an earlier kong does not exempt a later ordinary self-draw. A flower replacement resets the kong-win context, so it does not receive this exception either. Rob-added-kong and permitted rob-concealed-kong wins retain their separate robbed-player payment rule. The original responsibility declaration remains in the input snapshot; individual exempt payments are labeled self-draw, not responsibility.

Source recheck on 2026-10-03 confirmed the Chinese clause (text-export SHA-256 `8eed15d6d54c589f4b7819a0a907da693d055a66963fbb29cea3b6873b83f602`). The linked [English edition](https://docs.google.com/document/d/1a66AhGRZE6IJmA_nd-C7gIQfSJ7sXo_2-c4XgVnMpTQ/edit) uses broader liability wording and does not repeat this explicit exemption; this pack follows the Chinese clause and does not claim that the two editions are identical. The Chinese detailed payment paragraph also omits the exception; its summary supplies the explicit condition.

**Not automated:** seven/eight-flower wins, full passed-win history, claim priority/multiple winners, penalties, declaration timing, determining responsibility, or verifying early-win history. Seven/eight-flower holdings return `needsContext` without payment, even when an ordinary hand is also present, to avoid guessing whether a flower win was waived. Heavenly/earthly flags require explicit player confirmation of the source's conditions, including no disqualifying preceding dealer kong. Last discard is recorded but has no separate bonus in this pack. No seven-pairs rule is invented; a hand made of pairs succeeds only if it also has a permitted ordinary decomposition.

## Taiwan pack: tw-house-16

This is an explicitly defined **partial house preset**, not a national standard and not the complete rules of any commercial game. [Gametower's Taiwanese 16-tile table](https://www.gametower.com.tw/Games/Freeplay/MJ/Star31/Data/i_ingame-count.aspx) informed several pattern values, exclusions, and dealer progression. Its page also describes platform-specific options, declaration bonuses and ambiguous-hand behavior. Those cannot be silently combined into a universal Taiwanese preset.

The following is the app's own precise house contract. Five groups plus a pair form the winning hand, normally 17 physical ordinary tiles, plus one extra per declared kong. Flowers are separate. All legal decompositions and allocations of a discarded winning tile to a concealed group/eye are considered, and the greatest hand score wins. This remains true when custom values make a lower concealed-triplet tier worth more than a higher tier. A self-drawn tile cannot be reclassified as discard-completed.

| Pattern | Default tai | App definition / combination rule |
| --- | ---: | --- |
| Self draw / closed | 1 / 1 | Closed means no chow, pung, open or added kong; closed kongs are allowed. |
| Closed self draw | 3 | Replaces the separate closed and self-draw awards. |
| Three / four / five concealed triplets | 2 / 5 / 8 | Highest tier only; closed kongs count. A discard-completed triplet is exposed for this calculation. |
| All pungs | 4 | Five triplets/kongs; may stack with concealed tiers. |
| Half / full flush | 4 / 8 | Exactly one numbered suit, with / without honors. |
| All honors | 16 | Explicit house choice; editable. The reference publisher's page groups all-honor hands under its eight-tai flush description, so this preset intentionally differs. |
| Small / big dragons | 4 / 8 | Replaces individual dragon bonuses. |
| Individual dragon | 1 each | Applied only without small/big dragons. |
| Small / big winds | 8 / 16 | Additive with seat/round winds and other qualifying patterns in this house preset. |
| Seat / round wind | 1 each | May both apply to the same group. |
| Flat hand | 2 | Five chows, no honor or flower, discard win, multiple structural waits, and the winning tile can complete a concealed chow in this decomposition. Merely completing an eye does not qualify. |
| Single wait | 1 | Before the win, exactly one tile identity can complete a legal ordinary structure given this player's physical tiles. Public discards or opponents' concealed tiles are not used. |
| All exposed | 2 | All five groups are open and a discard completes the pair. Replaces single-wait bonus. |
| Matching flower | 1 each | Uses the printed number 1–4 for east–north, not potentially inconsistent botanical names. |
| Complete flower/season group | 2 each | Matching-flower award also applies. |
| Rob added kong / replacement / last live self draw | 1 each | Flower or kong replacement qualifies. Last discard has no extra award. |

This pack deliberately excludes heavenly/earthly wins, declared ready, early-ready, publisher-specific bonuses, special instant flower wins, seven-pairs extensions, and other house patterns not listed. Seven/eight flowers block automatic settlement. A declared heavenly/earthly flag is rejected as unsupported. It does not certify passed-win eligibility from the photo. The app's all-decomposition maximization differs from the publisher's documented triplet-first ambiguous-hand behavior. Closed-kong treatment, numeric flower mapping, all-honors value and additive wind treatment are explicit house choices, not claims about all Taiwanese tables.

For every liable payer:

```
dealer_addition = 1 + 2 × continuation_count, if winner or this payer is dealer
                 0 otherwise
payment = base + unit × min(hand_tai + dealer_addition, cap)
```

Defaults: base 50, unit 10, minimum 0, cap 100. A custom minimum is checked against hand tai before dealer additions; dealer tai do not establish minimum eligibility in this house contract. Discard and rob-added-kong wins charge only the discarder. Self draw charges each opponent independently, so only the dealer payer gets the dealer addition when a nondealer wins. At six hand tai, no continuations and a nondealer winner: another nondealer's discard costs 110; dealer discard costs 120; self draw collects 120 + 110 + 110. The app does not advance the dealer or continuation count automatically. Input range 0–100 continuations is an app boundary, not an adopted tournament continuation limit.

## Custom settings and validation

`defaultPatternValues(rules)` is the authoritative set of editable ordinary pattern values for the chosen family/flower option. Each accepts 0–100; zero disables that award. Shape definitions and exclusion relationships stay the same. Hong Kong limit patterns cannot be individually overridden. Unsupported override IDs, including values belonging only to a different family, cause an invalid result. When a flower option changes, the UI must remove now-inapplicable overrides or ask the user to reset them. Rule snapshots include family, version and all values; old saved transfers must not be silently recomputed.

HK custom minimum/cap remain within the supported conversion table (3–10). Taiwan allows cap 1–1000, with minimum no greater than cap. Unit accepts 1–1,000,000 and base 0–1,000,000. HK base is unused: its source table, multiplied by unit, is the entire payment basis.

Custom self-draw options are explicitly house rules:

- `preset`: HK each opponent pays half the table's discard value; Taiwan uses each payer's full formula.
- `fullEach`: HK each opponent pays the full discard table value; Taiwan has the same per-payer formula as its preset.
- `splitTotal`: HK divides one discard-table amount between the three opponents. Taiwan divides a single base-plus-tai amount, applying a dealer addition only if the winner is dealer. This deliberately removes payer-specific dealer weighting. Integer remainders go to the next payer indices in order after the winner, preserving the exact total.

Amounts are integers throughout. `settle` is an arithmetic layer for previously validated context; it does not certify a winning shape. Every successful `scoreHand` result validates the complete hand before calling it. Unsupported or below-minimum hands have no transfers. Every transfer has an explicit payer, recipient, amount and reason; balances sum to zero.

Physical validation covers 0–33 ordinary identities, no more than four copies including declared melds, unique numbered flowers, meld structure and count, winning tile in concealed tiles, seat bounds and incompatible event flags. Robbing a kong additionally allows only one copy of that identity in the winner's hand because the other player retains three. A consecutive replacement-kong chain can include at most one discard-fed open kong; subsequent kongs in that uninterrupted chain must be closed or added. HK initial dealing includes flower replacement before dealing is complete, so a confirmed heavenly hand can include an initial flower replacement but cannot follow a kong. The selected winning tile belongs in the ordinary concealed input; flowers and melds must not be counted there twice.

## Tests and evidence

Run from `app/` with the project Flutter SDK:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ../.tools/flutter/bin/flutter test test/domain
```

The test suite combines independently transcribed HK payout rows, original positive/negative scoring examples, exact boundary cases, and generated inputs. It does not use the implementation's payout map to manufacture its expected source values.

- 6,000 seeded structural hands: generated wins, single-tile mutations and unconstrained hands, across zero to five groups. An independent transfer-state oracle tracks sequences crossing rank boundaries; it does not share the engine's first-tile recursive decomposition algorithm. Each returned decomposition reconstructs the exact input multiset, and shuffled inputs preserve eligibility.
- 1,000 generated HK/Taiwan winning structures: tile reordering and complete numbered-suit rotation preserve score and payment balances. This is a metamorphic test, not an independent proof of every tai value.
- All eight HK payment rows across every winner/dealer/discarder assignment, three scales, self draw, discard and both robbing branches; source rows are literal fixtures. Additional tests cover responsibility, custom full/split policies and rounding. Another 1,152 combinations cover both robbery branches across every custom payment policy, payer position and two unit scales.
- 3,840 Taiwan settlement combinations exercise scores at zero and cap, every seat arrangement, counter boundaries and payment branches. These verify this documented house formula, not an external claim of universal Taiwanese rules.
- Targeted fixtures cover additive dragons, flower grouping, concealed-triplet allocation, ambiguous decompositions, nine-gates near misses, kong chains, limits, no-flower rules, flat-hand eye completion, immutable/serializable inputs, and invalid/missing state.
- A follow-up audit added four concrete counterexamples: non-monotonic custom concealed-triplet values, impossible consecutive discard-fed kongs, impossible HK responsibility structures, and initial flower replacement with heavenly win. The cases failed before their fixes. A 108-case matrix now exercises custom concealed-tier values and score caps for the same ambiguous winning tile.
- The 0.1.2 audit added a source-table matrix of 576 direct kong-replacement settlements across all eight payment rows, payer positions, policies and scales. A complete seven-faan hand independently expects 96 from each opponent, replacing the previous incorrect single charge of 288. Further complete-hand fixtures preserve ordinary/flower-replacement responsibility and both robbing branches. The two new exception tests were observed failing before the fix; the preservation tests already passed.

Passing tests establish regression protection for this contract. They do not replace independent experienced-player review, a full implementation of excluded event histories, or physical-phone recognition evaluation. No pack is advertised as having complete tournament adjudication.

Historical verification on 2026-10-02: 71 named domain tests passed. That version's domain coverage run recorded 496/501 executable lines in `scoring.dart` (99.0%) and 71/71 in `tiles.dart` (100%). Those are historical line-coverage counts, not a new measurement of engine 0.1.2, branch coverage or proof of rule completeness.

Verified on 2026-10-03 after the 0.1.2 fix: **76 named domain tests pass**, `flutter analyze lib/domain test/domain` reports no issues, and the complete Flutter application suite passes **206 tests**, including storage and widget integration. This verification did not produce a new native build or coverage report.
