# Mahjong rules and payment research

Research date: 2 October 2026. This document supports the application proposal. It is an initial source-backed catalogue and specification plan, not a claim that every regional rule has been exhaustively verified or implemented.

**Why presets must be precise.** “廣東牌” can mean Hong Kong-style mahjong locally, while Guangdong also has other families. “台牌” in Hong Kong can mean 港式十六張新章, which differs substantially from Taiwanese 16-tile mahjong. The [Hong Kong Mahjong Association](https://www.hkmahjong.org/rules) explicitly distinguishes these names. The app should display region, family, source, version, and house changes together.

Authority is scoped. An association rulebook specifies its competitions; a club rulebook specifies that club; a game publisher describes its own implementation. None automatically proves every household in that region plays identically. Use these as named baselines. Resolve conflicts by preserving distinct presets, not averaging values or silently mixing definitions.

**Proposed coverage catalogue.** The order is a product recommendation. “Source reviewed” means the cited relevant material was inspected, not that a complete executable specification or every edge case is ready.

| Family | Baseline and research state | Preferences or extra information to model |
| --- | --- | --- |
| 香港麻雀／清章／港式廣東牌 | HKMA Chinese rulebook retrieved and relevant scoring/payment sections reviewed | Minimum 番, cap, flowers, 半辣上/other lookup tables, 全銃/other policies, 包牌, 搶槓 |
| 港式台牌／十六張新章 | HKMA English rulebook retrieved; scoring, settlement, dealer and drag/cut sections reviewed | 17-tile winning forms, base, pattern exclusions, 連莊, 拉莊, rounding, flower/kong events |
| 台灣十六張 | Gametower scoring definitions reviewed; contrasting published Taiwanese tables found | 底/台 price, per-opponent dealer additions, 連一拉一, 門清自摸, flower matching, 平胡 and special-hand definitions |
| 日本立直四人 | SEGA MJ rules/payment tables reviewed; EMA 2025 rulebook located | 役/翻/符, red fives, dora indicators, open/closed state, dealer, honba, riichi deposits, rounding, furiten, multiple winners |
| 日本三人麻雀 | SEGA MJ three-player rules reviewed | Removed tiles, north treatment, tsumo-loss versus compensation policy, two payers, different repeat counters |
| 國標／MCR | UK Mahjong Association scoring summary reviewed; complete governing text still to reconcile | 81-pattern system, eight-point eligibility, flower treatment, exclusions, last-of-kind versus last-wall-tile |
| 中庸／Zung Jung | Creator's v3.3 basic rules and pattern list reviewed | Additive patterns, minimum variant, limit rules, responsibility and same-round immunity |
| 新加坡麻將 | SPGG January 2024 club rules reviewed | Animals, flowers, immediate transfers, payout tables, 平胡 restrictions, fresh-discard and 包 liabilities |
| 四川血戰到底 | Sichuan association competition document and group-standard text located; full settlement verification pending | Active players after wins, 定缺, 換三張, 槓 payments, 查叫/查花豬, caps, refunds and responsibility |
| 四川血流成河 | JJ publisher rules page located but rules image did not load; incomplete | Repeated wins, continued participation, event ledger and draw settlement; needs an accessible full baseline |
| 廣東推倒胡 | JJ's dated 2011 publisher rules reviewed | Self-draw restrictions, robbing kongs, kong liability, 馬 allocation, side transfers; numeric notation needs clarification |
| 廣東雞平胡／新章 | Family distinction documented by JJ; exact modern baseline not yet selected | Keep separate from HKMA Hong Kong rules; obtain full scoring, exclusions and settlement tables |
| 馬來西亞三人 | Descriptive reference reviewed; primary baseline remains unresolved | Fly/joker use, additional bonus tiles, three seats, instant payments, local score tables |
| 美式麻將 | NMJL current annual card confirmed; detailed licensed pack not obtained | Annual card identity, joker substitutions, concealed patterns, card value, self-pick and jokerless adjustments |

Also reserve separate research entries for 長沙／湖南, 武漢, 貴陽捉雞, 杭州, 上海, 福建/福州, and Chinese classical/Western classical play. Do not collapse these into “custom Cantonese.” They may introduce different eligibility, wildcards, bonus draws, losing-hand settlement, and event histories. These are proposed expansion candidates; this pass has not established their full payment specifications or ranked their popularity. [JJ family overview](https://www.jj.cn/news/320/20111025103000019369.shtml), [Bianfeng Wuhan introduction](https://www.gameabc.com/news/201708/4249.html), and [regional example from Game Tea](https://wap.gametea.com/mobile/128).

**Verified examples that drive the design.** All amounts below are abstract points. Examples from different presets are not comparable stake schedules.

Hong Kong association rules use a three-faan minimum and ten-faan limit. Their table gives discard/self-draw-per-opponent values of 32/16 at 3 faan, 64/32 at 4, 96/48 at 5, and 512/256 at 10. Thus a 3-faan discard win receives 32, while self-draw receives 48 in total. It is not safe to infer this table from a generic exponential formula. The rules also distinguish replacement after a kong from replacement after a flower. [HKMA 香港麻雀總例, scoring and conversion table](https://docs.google.com/document/d/1TgdYpE_5Qiht_lBco3BqN_ijZJDRWugwzRzv946raq0/edit).

HKMA's Hong Kong-style 16-tile rules use additive faan, discarder payment for a discard win, and each opponent's full-hand payment for self-draw. Dealer and continuation adjustments can differ by payer. They also describe deferred drag/cut settlement: qualifying later events can increase or reduce a carried debt. A final-hand photo alone cannot reconstruct that debt. The app must either record the session or request the outstanding obligations. [HKMA 16-Tile Modern Mahjong, Payment and Receipt, Drag and Cut](https://docs.google.com/document/d/1_TNf3YYWCCi5Z-SMssIRSB0dRPjfMCvbkTp5cCjLv9A/edit).

For Taiwanese house presets, support a configurable per-payer formula `base + tai × unit`, with dealer/repeat additions applied only where the preset specifies them. As a proposed arithmetic example, base 50, unit 10 and six already-final tai gives 110 per liable payer before any extra adjustment. Full-value self-draw would collect 330 if all three payer values were equal. The formula and payment style appear in a [published Taiwanese scoring guide](https://www.ezhula.com/mahjong-scoring); it is not adopted as a national standard.

Gametower's own table provides a concrete alternative baseline: 門清自摸 totals three tai without adding 門清 and 自摸 again, and dealer continuation uses the familiar 1, 3, 5 progression. Its page also includes platform-specific features. Do not carry a game-specific bonus into a general Taiwanese preset. The differing sources and even wording within guides require reconciliation before a preset is called verified. [Gametower Taiwanese scoring](https://www.gametower.com.tw/Games/Freeplay/MJ/Star31/Data/i_ingame-count.aspx).

Riichi payments depend on both han and fu, with limits, rounding, and dealer status. SEGA's four-player table gives a non-dealer 3 han 30 fu win as 3,900 on ron, or 1,000 from each non-dealer and 2,000 from the dealer on tsumo, before counters/deposits. The apparent 3,900 versus 4,000 discrepancy is a real rounding consequence. Do not simply divide the ron total. [SEGA four-player rules and tables](https://www.sega-mj.com/arcade/howto/play/rule/four.html).

Three-player Riichi needs a separate payment policy. SEGA's preset removes 2–8 man tiles, forbids chi, treats north as a value tile, and splits the missing north player's tsumo contribution between the remaining payers. Other sanma presets need their own confirmed north and payment rules. “Three-player mode” cannot merely hide one seat. [SEGA three-player rules](https://www.sega-mj.com/arcade/howto/play/rule/three.html).

For MCR, let H be the final hand points after validating eligibility. A discard win transfers H + 8 from the discarder and 8 from each other opponent; a self-draw transfers H + 8 from each opponent. For H = 24, that means 32 + 8 + 8 versus 32 + 32 + 32. The selected full specification must establish the eight-point qualification and flower handling separately, rather than treating every bonus as qualifying. [UKMA scoring summary](https://ukmahjong.co.uk/wp-content/uploads/2023/02/MCR-Summary.pdf) and [EMA tournament requirements](https://mahjong-europe.org/portal/images/docs/mcr_regulations.pdf).

Zung Jung v3.3 uses additive scoring. If H ≤ 25, each opponent pays H. For a larger hand won on discard, the two non-responsible players pay 25 each and the responsible player pays 3H − 50. On self-draw each pays H. At H = 70 that is 160/25/25 or 70/70/70. Same-round immunity can change who is responsible, so the latest discarder alone is insufficient context. [Creator's v3.3 rules](https://www.zj-mahjong.info/zj33_rules_eng.html).

SPGG's Singapore preset uses its own table and immediate payments. At three doubles its full and half prices are 8 and 4: an ordinary discard win pays 8/4/4, and self-draw uses full price from each opponent. Kong and animal/flower events can pay during the hand. Higher rows are not a simple doubling continuation, and the PDF contains special-case markings, so transcribe and verify the actual table before implementation. [SPGG January 2024 rules, rules 17–25](https://www.spgg.org.sg/web/content/114907/).

JJ's Guangdong 推倒胡 preset allows self-draw and robbing a kong rather than ordinary discard wins. Its payment section assigns specific responsibilities for different kongs and describes a separate 馬 settlement. However, it uses N both in an exponent expression and in a signed transfer-style list. That is not an implementation-ready formula without clarification and worked examples. Preserve the source as a candidate preset and record the ambiguity. [JJ publisher rules dated 25 October 2011](https://www.jj.cn/news/320/20111025103000019369.shtml).

**Preferences the settings system must cover.** Expose these only for relevant families, with valid combinations and a payment preview.

| Area | Options or data to support |
| --- | --- |
| Tile set and hand forms | 13/16-tile families; 3/4 players; flowers and animals; joker identity and limits; red fives; special winning shapes |
| Eligibility | Minimum score; which bonuses qualify toward it; allowed win methods; required suit absence; open/closed restrictions; passed-win restrictions |
| Pattern scoring | Pattern enabled/value; replacement versus addition; pair/sequence wait definitions; concealed-triplet handling; highest legal interpretation |
| Win events | Self-draw; discard; robbing added/concealed kongs where allowed; kong/flower replacement; final live draw; final discard; last available copy |
| Dealer and round | Seat/round winds; double wind; dealer additions; continuations; honba; renchan; initial-hand wins |
| Caps and conversion | Faan lookup table; linear 底/台; limits; multiple limit hands; unit price; per-payer and final-total rounding |
| Ordinary payments | Discarder-only; discarder plus other players; each opponent full value; fixed-total division; dealer weighting; sanma compensation |
| Exceptional payments | 包牌 source and order; multiple winners; kong/flower/animal transfers; refunds; bird/horse results; draw settlement |
| Session accounting | Deposits; carried debts; 拉莊/cut; settlement timing; round end; correction/undo; end-of-session unfinished balances |

Do not offer arbitrary combinations as an official preset. A custom combination should be clearly labelled and should reject contradictions, such as enabling a flower bonus while excluding flower tiles. Restrict edits to supported behaviours; completely new pattern logic requires a reviewed rule extension.

**What a scan cannot establish.** User confirmation or session records are required for the winning tile's role, self-draw versus discard, exposed versus concealed groups where presentation is ambiguous, who supplied a meld, event order, dealer and continuation state, final live draw versus final discard, furiten/passed-win history, dora indicators, declared listening, liability, and deferred debts. Some last-of-kind rules also need public tile information outside the winning hand. A question should appear only if that missing fact changes eligibility, scoring, or transfers.

**Required specification before a preset ships.** Every supported pack needs its entire scoring catalogue, exact definitions, special winning forms, stacking/exclusion matrix, minimum and cap treatment, payer formulas, rounding, event order, draw conditions, session transitions, and a source reference per disputed or non-obvious rule. Attach original examples demonstrating positive cases, near misses, conflicting patterns, and every payment branch. A manual editor alone is not proof the pack is correct.

Keep three readiness labels in development: identified, specified, and verified. The current work identifies the catalogue and verifies selected facts and examples; it does not mark any full engine as verified. Conflicting sources should be resolved into explicitly named variants or an outstanding issue. A source update creates a new pack version with a migration note, never a silent change to earlier hands.

**Additional sources and gaps.** The following references guide the next specification pass.

- [EMA rules index](https://mahjong-europe.org/portal/index.php?Itemid=101&id=12&option=com_content&view=category) and [Riichi 2025 book](https://mahjong-europe.org/portal/images/docs/Riichi-rules-2025-EN.pdf): index and revision notes were available, but the full PDF fetch failed in this pass. Pin the adopted edition and read its complete annotations before implementing an EMA preset.
- [Zung Jung 44-pattern list](https://www.zj-mahjong.info/zj33_patterns_eng.html): primary definition reference, with explicit pattern-series restrictions in the companion rules.
- [Sichuan association competition document](https://www.ssva.org.cn/upload/file/2023-10-08/6383235670424258795805165.pdf) and [group-standard PDF](https://www.ttbz.org.cn/Home/PdfFileStreamGet/c3QsMTEyODcw): located through indexed text; complete fetches failed. Do not certify all Sichuan payments from snippets.
- [JJ blood-flow rules page](https://www.jj.cn/news/320/20111024095800019325.shtml): the rules are an image that was inaccessible. Recover that content or select another complete publisher/organiser source before specifying its pack.
- [Mahjong Time Taiwanese scoring](https://mahjongtime.com/mahjong-taiwanese-scoring-2.html): useful evidence that published Taiwanese variants differ greatly; some examples contain inconsistent labels/numbers, so do not treat it as a universal authority.
- [Malaysian three-player overview](https://en.wikipedia.org/wiki/Three-player_mahjong#Malaysia): secondary discovery reference only. A named club or publisher baseline and independent local review are still needed for exact payments.
- [NMJL](https://www.nationalmahjonggleague.org/): confirms the 2026 rule card is current. The card's complete content and distribution permission were not obtained. American support requires an annual, appropriately licensed specification rather than invented pattern lists.

The HKMA rulebooks were retrieved as text from their public Google Docs exports after the web reader returned only the document shell. Their scoring text was inspected directly. Full third-party rulebooks have not been copied into this repository; this document contains original summaries and links.

This research establishes the architecture's necessary breadth and provides concrete starting baselines. Remaining source gaps are explicit work items in the development plan, particularly regional payment variants and complete pattern-by-pattern reconciliation.
