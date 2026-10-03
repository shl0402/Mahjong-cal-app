import 'dart:convert';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'branding.dart';
import 'data/local_store.dart';
import 'data/licenses.dart';
import 'domain/scoring.dart';
import 'domain/tiles.dart';
import 'ui/scan_page.dart';
import 'ui/tile_view.dart';
import 'ui/settings_page.dart';

const pine = Color(0xff194D40), cream = Color(0xffF6F4ED);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  runApp(MahjongApp(store: await LocalStore.open()));
}

class MahjongApp extends StatelessWidget {
  final LocalStore store;
  const MahjongApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appNameBilingual,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansTC',
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: pine,
        primary: pine,
        surface: cream,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        headlineSmall: TextStyle(fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    home: MahjongHome(store: store),
  );
}

class MahjongHome extends StatefulWidget {
  final LocalStore store;
  const MahjongHome({super.key, required this.store});
  @override
  State<MahjongHome> createState() => _HomeState();
}

class _HomeState extends State<MahjongHome> {
  late Rules rules;
  late List<SavedHand> history;
  Hand hand = Hand();
  int page = 0;
  @override
  void initState() {
    super.initState();
    rules = widget.store.readRules();
    history = widget.store.readHistory();
    if (widget.store.warning != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => notice(widget.store.warning!),
      );
    }
  }

  void notice(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  void update(Map<String, dynamic> changes) => setState(
    () => hand = Hand.fromJson({
      ...hand.toJson(),
      'circumstancesConfirmed': false,
      ...changes,
    }),
  );
  Future<bool> setRules(Rules next) async {
    final errors = validateRules(next);
    if (errors.isNotEmpty) {
      notice(errors.first);
      return false;
    }
    try {
      await widget.store.saveRules(next);
      if (mounted) {
        setState(() {
          final familyChanged = rules.family != next.family;
          rules = next;
          hand = Hand.fromJson({
            ...hand.toJson(),
            'circumstancesConfirmed': false,
            if (familyChanged) ...{
              'heavenly': false,
              'earthly': false,
              'liablePlayer': null,
              'continuations': 0,
              if (hand.source == WinSource.robConcealedKong) 'source': null,
            },
            if (!next.flowers) ...{
              'flowers': <int>[],
              if (hand.replacement == Replacement.flower) 'replacement': 'none',
            },
          });
        });
      }
      return true;
    } catch (_) {
      notice('設定未能儲存，請重試。');
      return false;
    }
  }

  Future<bool> replaceDraft() async {
    if (hand.concealed.isEmpty && hand.melds.isEmpty && hand.flowers.isEmpty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('替換目前手牌？'),
            content: const Text('未儲存的手牌及本局情況會被替換。已儲存記錄會保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('保留'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('替換'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> sample() async {
    if (!await replaceDraft()) return;
    final tiles = parseTiles(
      rules.family == RuleFamily.hongKong
          ? '123456789m123p55s'
          : '123456789m123456p55s',
    );
    setState(() {
      hand = Hand(
        concealed: tiles,
        winningTile: 22,
        source: WinSource.selfDraw,
      );
      page = 1;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: math.max(
        76,
        (MediaQuery.textScalerOf(context).scale(23) +
                    MediaQuery.textScalerOf(context).scale(10) +
                    MediaQuery.textScalerOf(context).scale(11)) *
                1.5 +
            16,
      ),
      title: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Container(
              width: 38,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pine,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '發',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appNameChinese,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    appNameEnglish,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: .3,
                      color: pine,
                    ),
                  ),
                  Text(
                    '${rules.title}${rules.custom ? ' · 自訂' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: pine),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (constraints.maxWidth >= 420 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3)
              ActionChip(
                avatar: const Icon(Icons.tune, size: 16),
                label: Text(
                  '${rules.title}${rules.custom ? ' · 自訂' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => setState(() => page = 3),
              )
            else
              IconButton(
                tooltip: '規則設定：${rules.title}${rules.custom ? ' · 自訂' : ''}',
                onPressed: () => setState(() => page = 3),
                icon: const Icon(Icons.tune),
              ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: IndexedStack(
            index: page,
            children: [
              ScanPage(
                active: page == 0,
                maximumTiles: rules.groupCount * 3 + 2,
                onAccepted: (tiles) async {
                  if (await replaceDraft()) {
                    setState(() {
                      hand = Hand(concealed: tiles);
                      page = 1;
                    });
                  }
                },
                onManual: () => setState(() => page = 1),
                onSample: sample,
              ),
              handPage(),
              historyPage(),
              SettingsPage(
                rules: rules,
                onChanged: (r) async {
                  await setRules(r);
                },
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) => setState(() => page = i),
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xffDBE9DF),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.document_scanner_outlined),
          selectedIcon: Icon(Icons.document_scanner),
          label: '掃描',
        ),
        NavigationDestination(
          icon: Icon(Icons.view_week_outlined),
          selectedIcon: Icon(Icons.view_week),
          label: '手牌',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: '記錄'),
        NavigationDestination(icon: Icon(Icons.tune), label: '規則'),
      ],
    ),
  );

  String player(int p) => '玩家 ${String.fromCharCode(65 + p)}';
  String seat(int p) => ['東', '南', '西', '北'][(p - hand.dealer + 4) % 4];
  Widget handPage() {
    final needed = (rules.groupCount - hand.melds.length) * 3 + 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        heading(
          context,
          'REVIEW YOUR HAND',
          '看清每一張，\n算清每一番。',
          '先核對牌面，再補上食糊情況。',
        ),
        section(
          '暗手牌  ${hand.concealed.length} / $needed',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hand.concealed.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('加入手牌，包括最後食糊的那一張。'),
                ),
              Wrap(
                spacing: 6,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < hand.concealed.length; i++)
                    TileView(
                      tile: hand.concealed[i],
                      selected: hand.winningTile == hand.concealed[i],
                      onTap: () => update({'winningTile': hand.concealed[i]}),
                      onLongPress: () => editTile(i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '點一下標記食糊牌（金框）；用「更正牌面」修改或刪除，也可長按牌面。',
                style: TextStyle(fontSize: 12, color: Color(0xff66746C)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: hand.concealed.isEmpty
                        ? null
                        : chooseTileToCorrect,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('更正牌面'),
                  ),
                  OutlinedButton.icon(
                    onPressed: addTiles,
                    icon: const Icon(Icons.add),
                    label: const Text('加牌'),
                  ),
                  TextButton.icon(
                    onPressed: hand.concealed.isEmpty
                        ? null
                        : () => update({
                            'concealed': hand.concealed.toList()..sort(),
                          }),
                    icon: const Icon(Icons.sort),
                    label: const Text('整理'),
                  ),
                  TextButton(onPressed: sample, child: const Text('載入示範')),
                ],
              ),
            ],
          ),
          trailing: IconButton(
            tooltip: '清空手牌',
            onPressed: () async {
              if (await replaceDraft()) setState(() => hand = Hand());
            },
            icon: const Icon(Icons.restart_alt),
          ),
        ),
        gap,
        section(
          '吃・碰・槓',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hand.melds.isEmpty)
                const Text(
                  '已亮出的牌分開加入，暗槓也在這裡。',
                  style: TextStyle(fontSize: 12, color: Color(0xff66746C)),
                ),
              for (var i = 0; i < hand.melds.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(meldLabel(hand.melds[i].kind)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 3,
                          children: hand.melds[i].tiles
                              .map((t) => TileView(tile: t, compact: true))
                              .toList(),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除此組',
                        onPressed: () => update({
                          'melds': (hand.melds.toList()..removeAt(i))
                              .map((m) => m.toJson())
                              .toList(),
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: hand.melds.length >= rules.groupCount
                    ? null
                    : addMeld,
                icon: const Icon(Icons.add),
                label: const Text('加入一組'),
              ),
            ],
          ),
        ),
        if (rules.flowers) ...[
          gap,
          section(
            '花牌',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var t = 34; t < 42; t++)
                      FilterChip(
                        label: Text(tileLabels[t]),
                        selected: hand.flowers.contains(t),
                        onSelected: (yes) => update({
                          'flowers': yes
                              ? [...hand.flowers, t]
                              : (hand.flowers.toList()..remove(t)),
                        }),
                      ),
                  ],
                ),
                const Text(
                  '對位花以實物上的 ①②③④ 為準。',
                  style: TextStyle(fontSize: 12, color: Color(0xff66746C)),
                ),
              ],
            ),
          ),
        ],
        gap,
        section(
          '這副牌怎樣食糊？',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in WinSource.values)
                    ChoiceChip(
                      label: Text(sourceLabel(s)),
                      selected: hand.source == s,
                      onSelected: (_) => update({
                        'source': s.name,
                        'lastTile': 'none',
                        'replacement': 'none',
                        'kongChain': 0,
                        'heavenly': false,
                        'earthly': false,
                        'liablePlayer': null,
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (c, size) => Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    field(
                      size,
                      dropdown<int>(
                        '食糊者',
                        hand.winner,
                        {
                          for (var i = 0; i < 4; i++)
                            i: '${player(i)} · ${seat(i)}',
                        },
                        (v) => update({
                          'winner': v,
                          'discarder': v == hand.discarder
                              ? (v + 1) % 4
                              : hand.discarder,
                          'liablePlayer': null,
                        }),
                      ),
                    ),
                    field(
                      size,
                      dropdown<int>(
                        '莊家',
                        hand.dealer,
                        {for (var i = 0; i < 4; i++) i: player(i)},
                        (v) => update({
                          'dealer': v,
                          'heavenly': false,
                          'earthly': false,
                        }),
                      ),
                    ),
                    if (!hand.selfDraw)
                      field(
                        size,
                        dropdown<int>(
                          hand.robbed ? '被搶槓者' : '出銃者',
                          hand.discarder,
                          {
                            for (var i = 0; i < 4; i++)
                              if (i != hand.winner) i: player(i),
                          },
                          (v) => update({'discarder': v}),
                        ),
                      ),
                    field(
                      size,
                      dropdown<int>('圈風', hand.roundWind, {
                        0: '東風圈',
                        1: '南風圈',
                        2: '西風圈',
                        3: '北風圈',
                      }, (v) => update({'roundWind': v})),
                    ),
                    if (rules.family == RuleFamily.taiwanese)
                      field(
                        size,
                        dropdown<int>('連莊次數', hand.continuations, {
                          for (var i = 0; i <= 10; i++)
                            i: i == 0 ? '未連莊' : '連 $i 拉 $i',
                        }, (v) => update({'continuations': v})),
                      ),
                  ],
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  '最後一張、補牌與特殊情況',
                  style: TextStyle(fontSize: 14),
                ),
                children: [
                  dropdown<LastTile>('最後一張', hand.lastTile, {
                    LastTile.none: '不是',
                    if (hand.selfDraw) LastTile.draw: '海底最後摸牌',
                    if (hand.source == WinSource.discard)
                      LastTile.discard: '河底出牌（預設不加分）',
                  }, (v) => update({'lastTile': v.name})),
                  gap,
                  if (hand.selfDraw) ...[
                    dropdown<Replacement>(
                      '食糊牌來源',
                      hand.replacement,
                      {
                        Replacement.none: '普通摸牌',
                        Replacement.kong: '槓後直接補牌',
                        Replacement.flower: '補花後直接補牌',
                      },
                      (v) => update({
                        'replacement': v.name,
                        'kongChain': v == Replacement.kong ? 1 : 0,
                      }),
                    ),
                    gap,
                    if (hand.replacement == Replacement.kong) ...[
                      dropdown<int>('連續槓次數', hand.kongChain, {
                        1: '一次',
                        2: '連續兩次',
                        3: '連續三次',
                        4: '連續四次',
                      }, (v) => update({'kongChain': v})),
                      gap,
                    ],
                  ],
                  if (rules.family == RuleFamily.hongKong) ...[
                    if (hand.selfDraw) ...[
                      dropdown<int>('已確認的包牌者', hand.liablePlayer ?? -1, {
                        -1: '沒有包牌',
                        for (var i = 0; i < 4; i++)
                          if (i != hand.winner) i: player(i),
                      }, (v) => update({'liablePlayer': v < 0 ? null : v})),
                      if (hand.replacement == Replacement.kong)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('香港牌例：槓後直接補牌食糊免包牌，三家按你選的自摸支付方式結算。'),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('天糊'),
                        subtitle: const Text('莊家起手食糊，未開槓'),
                        value: hand.heavenly,
                        onChanged: (v) => update({'heavenly': v}),
                      ),
                    ],
                    if (hand.source == WinSource.discard)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('地糊'),
                        subtitle: const Text('食莊家首張出牌；莊家亦未開暗槓'),
                        value: hand.earthly,
                        onChanged: (v) => update({'earthly': v}),
                      ),
                  ],
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '已核對牌面及本局情況',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '包括食糊牌、副露、花牌、過水及包牌。相機無法判斷這些歷史。',
                  style: TextStyle(fontSize: 12),
                ),
                value: hand.circumstancesConfirmed,
                onChanged: (v) =>
                    update({'circumstancesConfirmed': v ?? false}),
              ),
            ],
          ),
        ),
        gap,
        FilledButton.icon(
          onPressed: calculate,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('計算番數與支付'),
        ),
        const SizedBox(height: 10),
        Text(
          '${rules.title} · ${rules.subtitle}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Color(0xff66746C)),
        ),
      ],
    );
  }

  Future<void> tileSheet(
    String title,
    Widget Function(BuildContext, StateSetter) content,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                gap,
                content(ctx, refresh),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> addTiles() async {
    final selected = <int>[];
    await tileSheet(
      '加入暗手牌',
      (ctx, refresh) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TilePalette(onSelected: (t) => refresh(() => selected.add(t))),
          Text('已選 ${selected.length} 張 · 點選下方的牌可移除'),
          gap,
          if (selected.isNotEmpty)
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < selected.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: TileView(
                        tile: selected[i],
                        compact: true,
                        onTap: () => refresh(() => selected.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
          gap,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      update({
                        'concealed': [...hand.concealed, ...selected],
                      });
                      Navigator.pop(ctx);
                    },
              child: Text('加入 ${selected.length} 張'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> chooseTileToCorrect() async {
    int? selected;
    await tileSheet(
      '選擇要更正的牌',
      (ctx, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('先選要更正的牌，再選正確牌面；也可以刪除。'),
          gap,
          Wrap(
            spacing: 6,
            runSpacing: 10,
            children: [
              for (var i = 0; i < hand.concealed.length; i++)
                TileView(
                  key: ValueKey('choose-correction-$i'),
                  tile: hand.concealed[i],
                  onTap: () {
                    selected = i;
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || selected == null || selected! >= hand.concealed.length) {
      return;
    }
    await editTile(selected!);
  }

  Future<void> editTile(int i) => tileSheet(
    '更正 ${tileLabels[hand.concealed[i]]}',
    (ctx, refresh) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TilePalette(
          onSelected: (t) {
            final next = hand.concealed.toList();
            next[i] = t;
            update({'concealed': next, 'winningTile': null});
            Navigator.pop(ctx);
          },
        ),
        gap,
        TextButton.icon(
          onPressed: () {
            update({
              'concealed': hand.concealed.toList()..removeAt(i),
              'winningTile': null,
            });
            Navigator.pop(ctx);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('刪除這一張'),
        ),
      ],
    ),
  );
  Future<void> addMeld() async {
    var kind = MeldKind.pung;
    await tileSheet(
      '加入吃・碰・槓',
      (ctx, refresh) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final k in MeldKind.values)
                ChoiceChip(
                  label: Text(meldLabel(k)),
                  selected: k == kind,
                  onSelected: (_) => refresh(() => kind = k),
                ),
            ],
          ),
          gap,
          Text(kind == MeldKind.chow ? '點選順子第一張（例如一萬代表一二三萬）' : '點選這組牌的牌面'),
          gap,
          TilePalette(
            enabled: (t) => kind != MeldKind.chow || (t < 27 && t % 9 <= 6),
            onSelected: (t) {
              final meld = Meld(
                kind,
                kind == MeldKind.chow
                    ? [t, t + 1, t + 2]
                    : List.filled(kind.index >= 2 ? 4 : 3, t),
              );
              update({
                'melds': [...hand.melds.map((m) => m.toJson()), meld.toJson()],
              });
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void calculate() {
    final result = scoreHand(hand, rules);
    var saved = false, saving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => DraggableScrollableSheet(
          initialChildSize: .85,
          minChildSize: .4,
          maxChildSize: .95,
          expand: false,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
            children: [
              Text(
                result.status == ResultStatus.valid ? '這副牌，算好了。' : '還需要核對一下',
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${rules.title}${rules.custom ? ' · 自訂家規' : ''} · ${rules.family == RuleFamily.taiwanese ? '莊家台數另列在支付' : '半辣上換算'}',
                style: const TextStyle(color: Color(0xff66746C), fontSize: 12),
              ),
              gap,
              if (result.patterns.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: pine,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${result.score}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 60,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 5),
                        child: Text(
                          rules.family == RuleFamily.hongKong ? '番' : '台',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (result.status == ResultStatus.valid)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              '本手收入',
                              style: TextStyle(
                                color: Color(0xffBCD5CA),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '+${result.total}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              for (final m in result.messages)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    m,
                    style: const TextStyle(
                      color: Color(0xff9A5B20),
                      height: 1.5,
                    ),
                  ),
                ),
              gap,
              for (final p in result.patterns)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.label),
                  subtitle: Text(
                    p.reason,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '+${p.value}',
                    style: const TextStyle(
                      color: pine,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (result.transfers.isNotEmpty) ...[
                const Divider(height: 30),
                const Text(
                  '每位玩家支付',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final t in result.transfers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${player(t.from)} → ${player(t.to)}'),
                    subtitle: Text(t.reason),
                    trailing: Text(
                      '${t.amount}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              for (final m in result.excluded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    m,
                    style: const TextStyle(
                      color: Color(0xff66746C),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              gap,
              if (result.status == ResultStatus.valid)
                FilledButton.icon(
                  onPressed: saved || saving
                      ? null
                      : () async {
                          refresh(() => saving = true);
                          final next = [
                            SavedHand.capture(hand, rules, result),
                            ...history,
                          ];
                          try {
                            await widget.store.saveHistory(next);
                            if (mounted) setState(() => history = next);
                            if (ctx.mounted) refresh(() => saved = true);
                          } catch (_) {
                            notice('記錄未能儲存，請重試。');
                          } finally {
                            if (ctx.mounted) refresh(() => saving = false);
                          }
                        },
                  icon: Icon(saved ? Icons.check : Icons.bookmark_add_outlined),
                  label: Text(saved ? '已儲存在這部手機' : '儲存本手記錄'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('返回修改'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget historyPage() {
    final balances = List.filled(4, 0);
    for (final e in history.where(
      (e) => ruleSnapshotKey(e.rules) == ruleSnapshotKey(rules.toJson()),
    )) {
      for (var i = 0; i < 4; i++) {
        balances[i] += (e.result['balances'][i] as int);
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        heading(context, 'YOUR TABLE', '每一手，\n都有記錄。', '保留當時的規則與計算結果，只存在這部裝置。'),
        section(
          '目前規則的累計收支',
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              for (var i = 0; i < 4; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player(i),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff66746C),
                      ),
                    ),
                    Text(
                      '${balances[i] > 0 ? '+' : ''}${balances[i]}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: balances[i] < 0 ? const Color(0xffA8433E) : pine,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        gap,
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 45),
            child: Column(
              children: [
                const Icon(Icons.history, size: 48, color: Color(0xffACB9AF)),
                gap,
                const Text('還沒有已儲存的牌局'),
                TextButton(onPressed: sample, child: const Text('用示範手牌試算')),
              ],
            ),
          ),
        for (final e in history)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xffE7EFE7),
                  child: Text(
                    '${e.result['score']}',
                    style: const TextStyle(
                      color: pine,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  '${Rules.fromJson(e.rules).title} · ${sourceLabel(Hand.fromJson(e.hand).source!)}',
                ),
                subtitle: Text(e.date.substring(0, 16).replaceFirst('T', ' ')),
                trailing: Text(
                  '+${e.result['total']}',
                  style: const TextStyle(
                    color: pine,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                onTap: () => showSaved(e),
              ),
            ),
          ),
      ],
    );
  }

  void showSaved(SavedHand e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已儲存的牌局', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '${Rules.fromJson(e.rules).title} · 規則版本 ${e.result['engineVersion']}',
              ),
              gap,
              Wrap(
                spacing: 4,
                runSpacing: 6,
                children: Hand.fromJson(e.hand).concealed
                    .map((t) => TileView(tile: t, compact: true))
                    .toList(),
              ),
              gap,
              for (final p in e.result['patterns'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p['label']),
                  trailing: Text('+${p['value']}'),
                ),
              for (final t in e.result['transfers'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${player(t['from'])} → ${player(t['to'])}'),
                  trailing: Text('${t['amount']}'),
                ),
              gap,
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (!await replaceDraft()) return;
                  if (!await setRules(Rules.fromJson(e.rules))) return;
                  if (mounted) {
                    setState(() {
                      hand = Hand.fromJson({
                        ...e.hand,
                        'circumstancesConfirmed': false,
                      });
                      page = 1;
                    });
                  }
                },
                child: const Text('載入為新草稿'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final next = history.where((x) => x.id != e.id).toList();
                  try {
                    await widget.store.saveHistory(next);
                    if (mounted) setState(() => history = next);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('已移除記錄'),
                          action: SnackBarAction(
                            label: '復原',
                            onPressed: () async {
                              final restored = [e, ...history]
                                ..sort((a, b) => b.date.compareTo(a.date));
                              try {
                                await widget.store.saveHistory(restored);
                                if (mounted) setState(() => history = restored);
                              } catch (_) {
                                notice('未能復原，請重試。');
                              }
                            },
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    notice('記錄未能移除。');
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('移除這手記錄'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const gap = SizedBox(height: 16);
String ruleSnapshotKey(Map<String, dynamic> values) {
  final sorted = SplayTreeMap<String, dynamic>.from(values);
  if (sorted['overrides'] is Map) {
    sorted['overrides'] = SplayTreeMap<String, dynamic>.from(
      sorted['overrides'],
    );
  }
  return jsonEncode(sorted);
}

Widget heading(
  BuildContext context,
  String eyebrow,
  String title,
  String subtitle,
) => Padding(
  padding: const EdgeInsets.only(bottom: 22),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: pine,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 7),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xff606B64), height: 1.6),
      ),
    ],
  ),
);
Widget section(String title, Widget child, {Widget? trailing}) => Card(
  child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        gap,
        child,
      ],
    ),
  ),
);
Widget field(BoxConstraints c, Widget child) => SizedBox(
  width: c.maxWidth < 290 ? c.maxWidth : (c.maxWidth - 12) / 2,
  child: child,
);
Widget dropdown<T>(
  String label,
  T value,
  Map<T, String> choices,
  ValueChanged<T> changed,
) => DropdownButtonFormField<T>(
  key: ValueKey('$label-$value'),
  initialValue: choices.containsKey(value) ? value : null,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: choices.entries
      .map(
        (e) => DropdownMenuItem<T>(
          value: e.key,
          child: Text(
            e.value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      )
      .toList(),
  onChanged: (v) {
    if (v != null) changed(v);
  },
);
String sourceLabel(WinSource s) => switch (s) {
  WinSource.discard => '出銃',
  WinSource.selfDraw => '自摸',
  WinSource.robAddedKong => '搶加槓',
  WinSource.robConcealedKong => '搶暗槓',
};
String meldLabel(MeldKind k) => switch (k) {
  MeldKind.chow => '吃',
  MeldKind.pung => '碰',
  MeldKind.openKong => '明槓',
  MeldKind.closedKong => '暗槓',
  MeldKind.addedKong => '加槓',
};
