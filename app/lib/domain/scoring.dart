import 'dart:math' as math;

import 'tiles.dart';

enum RuleFamily { hongKong, taiwanese }

enum WinSource { discard, selfDraw, robAddedKong, robConcealedKong }

enum LastTile { none, draw, discard }

enum Replacement { none, flower, kong }

enum PaymentMode { preset, fullEach, splitTotal }

enum ResultStatus { valid, incomplete, invalid, belowMinimum, needsContext }

class Rules {
  static const version = '0.1.2';
  final RuleFamily family;
  final int minimum;
  final int cap;
  final bool flowers;
  final int base;
  final int unit;
  final PaymentMode payment;
  final Map<String, int> overrides;
  Rules({
    this.family = RuleFamily.hongKong,
    this.minimum = 3,
    this.cap = 10,
    this.flowers = true,
    this.base = 50,
    this.unit = 1,
    this.payment = PaymentMode.preset,
    Map<String, int> overrides = const {},
  }) : overrides = Map.unmodifiable(overrides);
  factory Rules.taiwanese() => Rules(
    family: RuleFamily.taiwanese,
    minimum: 0,
    cap: 100,
    base: 50,
    unit: 10,
  );
  int get groupCount => family == RuleFamily.hongKong ? 4 : 5;
  String get id =>
      family == RuleFamily.hongKong ? 'hk-hand-2025' : 'tw-house-16';
  String get title => family == RuleFamily.hongKong ? '香港牌' : '台灣 16 張';
  String get subtitle => family == RuleFamily.hongKong
      ? '參考 HKMA 2025 · 花糊待支援'
      : '基本家規 · 部分台型 · 底加台';
  bool get custom =>
      overrides.isNotEmpty ||
      payment != PaymentMode.preset ||
      !flowers ||
      (family == RuleFamily.hongKong
          ? minimum != 3 || cap != 10
          : minimum != 0 || cap != 100);
  Rules copyWith({
    int? minimum,
    int? cap,
    bool? flowers,
    int? base,
    int? unit,
    PaymentMode? payment,
    Map<String, int>? overrides,
  }) => Rules(
    family: family,
    minimum: minimum ?? this.minimum,
    cap: cap ?? this.cap,
    flowers: flowers ?? this.flowers,
    base: base ?? this.base,
    unit: unit ?? this.unit,
    payment: payment ?? this.payment,
    overrides: overrides ?? this.overrides,
  );
  Map<String, dynamic> toJson() => {
    'family': family.name,
    'minimum': minimum,
    'cap': cap,
    'flowers': flowers,
    'base': base,
    'unit': unit,
    'payment': payment.name,
    'overrides': overrides,
    'version': version,
  };
  factory Rules.fromJson(Map<String, dynamic> j) => Rules(
    family: RuleFamily.values.byName(j['family']),
    minimum: j['minimum'],
    cap: j['cap'],
    flowers: j['flowers'],
    base: j['base'],
    unit: j['unit'],
    payment: PaymentMode.values.byName(j['payment']),
    overrides: Map<String, int>.from(j['overrides'] ?? {}),
  );
}

class Hand {
  final List<int> concealed;
  final List<Meld> melds;
  final List<int> flowers;
  final int? winningTile;
  final WinSource? source;
  final int winner, discarder, dealer, roundWind, continuations;
  final LastTile lastTile;
  final Replacement replacement;
  final int kongChain;
  final int? liablePlayer;
  final bool heavenly, earthly;

  /// Circumstances confirmed by the player, including passed-win restrictions.
  final bool circumstancesConfirmed;
  Hand({
    Iterable<int> concealed = const [],
    Iterable<Meld> melds = const [],
    Iterable<int> flowers = const [],
    this.winningTile,
    this.source,
    this.winner = 0,
    this.discarder = 1,
    this.dealer = 0,
    this.roundWind = 0,
    this.continuations = 0,
    this.lastTile = LastTile.none,
    this.replacement = Replacement.none,
    this.kongChain = 0,
    this.liablePlayer,
    this.heavenly = false,
    this.earthly = false,
    this.circumstancesConfirmed = false,
  }) : concealed = List.unmodifiable(concealed),
       melds = List.unmodifiable(melds),
       flowers = List.unmodifiable(flowers);
  int get seatWind => (winner - dealer + 4) % 4;
  bool get selfDraw => source == WinSource.selfDraw;
  bool get robbed =>
      source == WinSource.robAddedKong || source == WinSource.robConcealedKong;
  List<int> get ordinaryTiles => [
    ...concealed,
    ...melds.expand((m) => m.tiles),
  ];
  Map<String, dynamic> toJson() => {
    'concealed': concealed,
    'melds': melds.map((m) => m.toJson()).toList(),
    'flowers': flowers,
    'winningTile': winningTile,
    'source': source?.name,
    'winner': winner,
    'discarder': discarder,
    'dealer': dealer,
    'roundWind': roundWind,
    'continuations': continuations,
    'lastTile': lastTile.name,
    'replacement': replacement.name,
    'kongChain': kongChain,
    'liablePlayer': liablePlayer,
    'heavenly': heavenly,
    'earthly': earthly,
    'circumstancesConfirmed': circumstancesConfirmed,
  };
  factory Hand.fromJson(Map<String, dynamic> j) => Hand(
    concealed: (j['concealed'] as List).cast<int>(),
    melds: (j['melds'] as List).map(
      (m) => Meld.fromJson(Map<String, dynamic>.from(m)),
    ),
    flowers: (j['flowers'] as List).cast<int>(),
    winningTile: j['winningTile'],
    source: j['source'] == null ? null : WinSource.values.byName(j['source']),
    winner: j['winner'],
    discarder: j['discarder'],
    dealer: j['dealer'],
    roundWind: j['roundWind'],
    continuations: j['continuations'],
    lastTile: LastTile.values.byName(j['lastTile']),
    replacement: Replacement.values.byName(j['replacement']),
    kongChain: j['kongChain'],
    liablePlayer: j['liablePlayer'],
    heavenly: j['heavenly'],
    earthly: j['earthly'],
    circumstancesConfirmed: j['circumstancesConfirmed'],
  );
}

class Pattern {
  final String id, label, reason;
  final int value;
  const Pattern(this.id, this.label, this.value, this.reason);
}

class Transfer {
  final int from, to, amount;
  final String reason;
  const Transfer(this.from, this.to, this.amount, this.reason);
  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'amount': amount,
    'reason': reason,
  };
}

class ScoreResult {
  final ResultStatus status;
  final List<String> messages;
  final List<Pattern> patterns;
  final List<Transfer> transfers;
  final int rawScore, score;
  final List<String> excluded;
  ScoreResult(
    this.status, {
    List<String> messages = const [],
    List<Pattern> patterns = const [],
    List<Transfer> transfers = const [],
    this.rawScore = 0,
    this.score = 0,
    List<String> excluded = const [],
  }) : messages = List.unmodifiable(messages),
       patterns = List.unmodifiable(patterns),
       transfers = List.unmodifiable(transfers),
       excluded = List.unmodifiable(excluded);
  int get total => transfers.fold(0, (a, t) => a + t.amount);
  List<int> get balances {
    final b = List.filled(4, 0);
    for (final t in transfers) {
      b[t.from] -= t.amount;
      b[t.to] += t.amount;
    }
    return b;
  }
}

const hkDiscardTable = {
  3: 32,
  4: 64,
  5: 96,
  6: 128,
  7: 192,
  8: 256,
  9: 384,
  10: 512,
};
const patternNames = {
  'chows': '平糊',
  'selfDraw': '自摸',
  'closed': '門前清',
  'noFlowers': '無花',
  'seatFlower': '正花',
  'flowerSet': '一台花',
  'dragon': '三元牌',
  'seatWind': '門風',
  'roundWind': '圈風',
  'mixedTerminals': '花么',
  'robKong': '搶槓',
  'kongWin': '槓上開花',
  'lastDraw': '海底撈月',
  'halfFlush': '混一色',
  'allPungs': '對對糊',
  'smallDragons': '小三元',
  'bigDragons': '大三元',
  'fullFlush': '清一色',
  'closedSelfDraw': '門清自摸',
  'threeConcealed': '三暗刻',
  'fourConcealed': '四暗刻',
  'fiveConcealed': '五暗刻',
  'singleWait': '獨聽',
  'allExposed': '全求',
  'allHonors': '字一色',
  'bigWinds': '大四喜',
  'smallWinds': '小四喜',
};

/// Only these implemented ordinary scores may be changed. Hong Kong limit
/// hands remain fixed at ten before the user's cap; changing their definitions
/// requires a separate rules pack rather than a silent numeric override.
Map<String, int> defaultPatternValues(Rules r) => {
  if (r.family == RuleFamily.hongKong) ...{
    'chows': 1,
    'selfDraw': 1,
    'dragon': 1,
    'seatWind': 1,
    'roundWind': 1,
    'mixedTerminals': 1,
    'robKong': 1,
    'kongWin': 1,
    'lastDraw': 1,
    'halfFlush': 3,
    'allPungs': 3,
    'smallDragons': 3,
    'bigDragons': 5,
    'fullFlush': 7,
    if (!r.flowers) 'closed': 1,
    if (r.flowers) ...{'noFlowers': 1, 'seatFlower': 1, 'flowerSet': 1},
  } else ...{
    'chows': 2,
    'selfDraw': 1,
    'closed': 1,
    'closedSelfDraw': 3,
    'dragon': 1,
    'seatWind': 1,
    'roundWind': 1,
    'robKong': 1,
    'kongWin': 1,
    'lastDraw': 1,
    'halfFlush': 4,
    'allPungs': 4,
    'smallDragons': 4,
    'bigDragons': 8,
    'fullFlush': 8,
    'threeConcealed': 2,
    'fourConcealed': 5,
    'fiveConcealed': 8,
    'singleWait': 1,
    'allExposed': 2,
    'allHonors': 16,
    'bigWinds': 16,
    'smallWinds': 8,
    if (r.flowers) ...{'seatFlower': 1, 'flowerSet': 2},
  },
};

List<String> validateRules(Rules r) {
  final errors = <String>[];
  if (r.minimum < 0 || r.minimum > r.cap) errors.add('起糊分數不能大於上限。');
  if (r.family == RuleFamily.hongKong &&
      (r.minimum < 3 || r.cap > 10 || r.cap < 3)) {
    errors.add('目前香港牌換算表只支援 3–10 番。');
  }
  if (r.family == RuleFamily.taiwanese && (r.cap < 1 || r.cap > 1000)) {
    errors.add('台數上限需為 1–1000。');
  }
  if (r.unit < 1 || r.unit > 1000000 || r.base < 0 || r.base > 1000000) {
    errors.add('底與單位超出支援範圍。');
  }
  if (r.overrides.entries.any(
    (e) =>
        !defaultPatternValues(r).containsKey(e.key) ||
        e.value < 0 ||
        e.value > 100,
  )) {
    errors.add('自訂番種或分值無效。');
  }
  return errors;
}

List<String> validateHand(Hand h, Rules r) {
  final errors = <String>[];
  if ([
    h.winner,
    h.discarder,
    h.dealer,
    h.roundWind,
  ].any((v) => v < 0 || v > 3)) {
    errors.add('風位或玩家無效。');
  }
  if (h.continuations < 0 || h.continuations > 100) errors.add('連莊次數無效。');
  if (h.liablePlayer != null &&
      (h.liablePlayer! < 0 ||
          h.liablePlayer! > 3 ||
          h.liablePlayer == h.winner)) {
    errors.add('包牌者必須為其他玩家。');
  }
  if (h.source != null && !h.selfDraw && h.discarder == h.winner) {
    errors.add('出銃者不能是食糊者。');
  }
  if (h.melds.length > r.groupCount) errors.add('副露組數過多。');
  for (final m in h.melds) {
    final sorted = m.tiles.toList()..sort();
    if (sorted.any((t) => t < 0 || t >= 34) ||
        sorted.length != (m.isKong ? 4 : 3)) {
      errors.add('副露牌數或牌面無效。');
      continue;
    }
    if (m.kind == MeldKind.chow) {
      if (sorted.first >= 27 ||
          sorted.first ~/ 9 != sorted.last ~/ 9 ||
          sorted[1] != sorted[0] + 1 ||
          sorted[2] != sorted[1] + 1) {
        errors.add('吃牌必須同一花色連續三張。');
      }
    } else if (sorted.toSet().length != 1) {
      errors.add('碰或槓必須是相同牌。');
    }
  }
  final counts = List.filled(34, 0);
  for (final t in h.ordinaryTiles) {
    if (t < 0 || t >= 34) {
      errors.add('手牌有未知或不支援的牌。');
    } else {
      counts[t]++;
    }
  }
  if (counts.any((n) => n > 4)) errors.add('相同牌最多只有四張。');
  // The robbed player's three remaining copies are outside this hand. Merely
  // checking this hand's maximum of four would admit impossible rob-kong wins.
  if (h.robbed &&
      h.winningTile != null &&
      h.winningTile! >= 0 &&
      h.winningTile! < 34 &&
      counts[h.winningTile!] > 1) {
    errors.add('搶槓牌在本手只能有一張，另外三張仍屬開槓者。');
  }
  if (h.flowers.any((t) => t < 34 || t >= 42) ||
      h.flowers.toSet().length != h.flowers.length) {
    errors.add('花牌不可重複，並須標明編號。');
  }
  if (!r.flowers && h.flowers.isNotEmpty) errors.add('這個規則沒有花牌。');
  if (h.winningTile != null && !h.concealed.contains(h.winningTile)) {
    errors.add('食糊牌必須在暗手牌內。');
  }
  if (h.lastTile == LastTile.draw && !h.selfDraw) errors.add('海底摸牌必須是自摸。');
  if (h.lastTile == LastTile.discard && h.source != WinSource.discard) {
    errors.add('河底出牌必須是普通出銃。');
  }
  if (h.replacement != Replacement.none && !h.selfDraw) {
    errors.add('補牌食糊必須是自摸。');
  }
  if (h.replacement == Replacement.flower && h.flowers.isEmpty) {
    errors.add('花後補牌需要花牌。');
  }
  if (h.kongChain < 0 || h.kongChain > h.melds.where((m) => m.isKong).length) {
    errors.add('連續槓次數與副露不符。');
  }
  final selfDeclaredKongs = h.melds
      .where(
        (m) => m.kind == MeldKind.closedKong || m.kind == MeldKind.addedKong,
      )
      .length;
  final hasDiscardKong = h.melds.any((m) => m.kind == MeldKind.openKong);
  if (h.kongChain > selfDeclaredKongs + (hasDiscardKong ? 1 : 0)) {
    errors.add('連續槓最多只有第一槓可來自他家出牌，其後須為暗槓或加槓。');
  }
  if (h.replacement == Replacement.kong && h.kongChain < 1) {
    errors.add('槓後補牌需至少一次槓。');
  }
  if (h.replacement != Replacement.kong && h.kongChain != 0) {
    errors.add('補花或普通摸牌會中斷連槓。');
  }
  if (h.heavenly &&
      (h.winner != h.dealer ||
          !h.selfDraw ||
          h.melds.isNotEmpty ||
          h.replacement == Replacement.kong)) {
    errors.add('天糊必須是莊家起手，未吃碰槓。');
  }
  if (h.earthly &&
      (h.winner == h.dealer ||
          h.source != WinSource.discard ||
          h.discarder != h.dealer ||
          h.melds.isNotEmpty)) {
    errors.add('此牌例的地糊需食莊家首張出牌。');
  }
  if (h.heavenly && h.earthly) errors.add('天糊與地糊不可同時成立。');
  if ((h.heavenly || h.earthly) && h.lastTile != LastTile.none) {
    errors.add('起手食糊不能同時是最後一張。');
  }
  if (r.family == RuleFamily.taiwanese && (h.heavenly || h.earthly)) {
    errors.add('台灣家規的天胡／地胡尚未支援。');
  }
  if (r.family == RuleFamily.taiwanese && h.liablePlayer != null) {
    errors.add('此台灣家規不使用包牌。');
  }
  if (r.family == RuleFamily.hongKong && h.selfDraw && h.liablePlayer != null) {
    final dragons = h.melds
        .where(
          (m) =>
              m.isTriplet &&
              m.tiles.isNotEmpty &&
              m.tiles.first >= 31 &&
              m.tiles.first < 34,
        )
        .toList();
    final twelveTiles = h.melds.length == 4 && h.melds.any((m) => m.isOpen);
    final exposedDragons =
        dragons.map((m) => m.tiles.first).toSet().length == 3 &&
        dragons.any((m) => m.isOpen);
    if (!twelveTiles && !exposedDragons) {
      errors.add('此香港牌例包牌需有十二章或三組已宣告三元牌，並有他家供牌。');
    }
  }
  return errors.toSet().toList();
}

ScoreResult scoreHand(Hand h, Rules r) {
  final errors = [...validateRules(r), ...validateHand(h, r)];
  if (errors.isNotEmpty) {
    return ScoreResult(ResultStatus.invalid, messages: errors);
  }
  final missing = <String>[];
  if (h.source == null) missing.add('請選擇自摸、出銃或搶槓。');
  if (!h.circumstancesConfirmed) missing.add('請確認本局情況，包括過水、包牌及最後摸牌。');
  // Instant flower wins require additional declaration history; never guess it.
  if (h.flowers.length >= 7) {
    return ScoreResult(
      ResultStatus.needsContext,
      messages: ['七／八花的即時花糊宣告仍需核對。此版本不自動結算花糊。'],
    );
  }
  final expected = (r.groupCount - h.melds.length) * 3 + 2;
  if (h.concealed.length != expected) {
    return ScoreResult(
      h.concealed.length < expected
          ? ResultStatus.incomplete
          : ResultStatus.invalid,
      messages: ['暗手牌應有 $expected 張（包括食糊牌），目前 ${h.concealed.length} 張。'],
    );
  }
  if (h.winningTile == null) missing.add('請點選食糊的那一張牌。');
  if (missing.isNotEmpty) {
    return ScoreResult(ResultStatus.needsContext, messages: missing);
  }
  final orphan =
      r.family == RuleFamily.hongKong &&
      h.melds.isEmpty &&
      isThirteenOrphans(h.concealed);
  if (h.source == WinSource.robConcealedKong && !orphan) {
    return ScoreResult(ResultStatus.invalid, messages: ['只有十三么可以在此牌例搶暗槓。']);
  }
  final parts = decompose(h.concealed, r.groupCount - h.melds.length);
  if (!orphan && parts.isEmpty) {
    return ScoreResult(ResultStatus.invalid, messages: ['這副牌不能組成有效食糊牌型。']);
  }
  final variants = <List<Pattern>>[];
  if (orphan) {
    variants.add([const Pattern('orphans', '十三么', 10, '十三種么九字牌齊全，加一對。')]);
  }
  for (final d in parts) {
    // The winning identity can occur in more than one concealed group. House
    // values may be non-monotonic, so maximizing the number of hidden pungs is
    // not equivalent to maximizing points. Score each legal allocation.
    final roles = <_WinningRole>{
      if (h.selfDraw)
        _WinningRole.selfDraw
      else ...{
        if (d.pair == h.winningTile) _WinningRole.pair,
        for (final m in d.groups)
          if (m.tiles.contains(h.winningTile))
            m.isTriplet ? _WinningRole.pung : _WinningRole.chow,
      },
    };
    for (final role in roles) {
      variants.add(_patterns(h, r, d, role));
    }
  }
  variants.sort(
    (a, b) => b
        .fold<int>(0, (n, p) => n + p.value)
        .compareTo(a.fold<int>(0, (n, p) => n + p.value)),
  );
  final patterns = variants.first;
  final raw = patterns.fold<int>(0, (n, p) => n + p.value);
  final total = math.min(raw, r.cap);
  if (total < r.minimum) {
    return ScoreResult(
      ResultStatus.belowMinimum,
      patterns: patterns,
      rawScore: raw,
      score: total,
      messages: [
        '共 $total ${r.family == RuleFamily.hongKong ? '番' : '台'}，未達 ${r.minimum} 起糊。',
      ],
    );
  }
  final transfers = settle(h, r, total);
  final excluded = <String>[];
  if (patterns.any((p) => p.id == 'closedSelfDraw')) {
    excluded.add('門清自摸已包含門清與自摸，沒有重複加算。');
  }
  if (r.family == RuleFamily.taiwanese &&
      patterns.any((p) => p.id == 'bigDragons' || p.id == 'smallDragons')) {
    excluded.add('此家規的三元大牌已包含個別三元牌台數。');
  }
  if (r.family == RuleFamily.hongKong &&
      patterns.any((p) => hkLimitPatterns.contains(p.id))) {
    excluded.add('例牌依上限結算，不再累加普通番種。');
  }
  if (h.replacement == Replacement.flower && r.family == RuleFamily.hongKong) {
    excluded.add('香港牌補花後食糊不計槓上自摸。');
  }
  return ScoreResult(
    ResultStatus.valid,
    patterns: patterns,
    rawScore: raw,
    score: total,
    transfers: transfers,
    excluded: excluded,
    messages: raw > total ? ['已套用 $total 上限。'] : [],
  );
}

const hkLimitPatterns = {
  'allHonors',
  'bigWinds',
  'smallWinds',
  'fourHidden',
  'fourKongs',
  'allTerminals',
  'heavenly',
  'earthly',
  'doubleKongWin',
  'nineGates',
  'orphans',
};

enum _WinningRole { selfDraw, pair, chow, pung }

List<Pattern> _patterns(Hand h, Rules r, Decomposition d, _WinningRole role) {
  final hk = r.family == RuleFamily.hongKong;
  final groups = [...h.melds, ...d.groups];
  final triplets = groups.where((m) => m.isTriplet).toList();
  final ts = triplets.map((m) => m.tiles.first).toSet();
  final all = h.ordinaryTiles;
  final suits = all.where((t) => t < 27).map((t) => t ~/ 9).toSet();
  final honors = all.any(isHonor);
  final closed = h.melds.every((m) => !m.isOpen);
  final dragonCount = ts.where((t) => t >= 31).length;
  final windCount = ts.where((t) => t >= 27 && t <= 30).length;
  var concealedTriplets =
      d.groups.where((m) => m.isTriplet).length +
      h.melds.where((m) => m.kind == MeldKind.closedKong).length;
  if (role == _WinningRole.pung) concealedTriplets--;
  final p = <Pattern>[];
  void add(String id, int n, String why, {String? label}) {
    final value = r.overrides[id] ?? n;
    if (value > 0) {
      p.add(Pattern(id, label ?? patternNames[id] ?? id, value, why));
    }
  }

  if (hk) {
    final limits = <Pattern>[];
    void limit(String id, String name, String why) =>
        limits.add(Pattern(id, name, 10, why));
    if (suits.isEmpty) limit('allHonors', '全番子', '全副牌由字牌組成。');
    if (windCount == 4) limit('bigWinds', '大四喜', '四組風牌刻／槓。');
    if (windCount == 3 && d.pair >= 27 && d.pair <= 30) {
      limit('smallWinds', '小四喜', '三組風牌刻／槓，另一風牌作眼。');
    }
    if (concealedTriplets == 4 && h.melds.every((m) => !m.isKong)) {
      limit('fourHidden', '坎坎糊', '四暗刻，沒有槓；出銃完成眼。');
    }
    if (h.melds.where((m) => m.isKong).length == 4) {
      limit('fourKongs', '十八羅漢', '四個已宣告的槓。');
    }
    if (all.every(isTerminal)) limit('allTerminals', '清么九', '只有一、九數牌。');
    if (h.heavenly) limit('heavenly', '天糊', '已確認莊家起手食糊。');
    if (h.earthly) limit('earthly', '地糊', '已確認食莊家首張出牌。');
    if (h.kongChain >= 2) limit('doubleKongWin', '槓上槓自摸', '連續槓後直接補牌食糊。');
    if (h.melds.isEmpty && suits.length == 1 && !honors) {
      final c = List.filled(9, 0);
      for (final t in all) {
        c[t % 9]++;
      }
      final before = List<int>.of(c);
      before[h.winningTile! % 9]--;
      bool base(List<int> x) =>
          x[0] >= 3 && x[8] >= 3 && x.sublist(1, 8).every((n) => n >= 1);
      if (base(c) && (h.selfDraw || base(before))) {
        limit('nineGates', '九子連環', '門清九蓮形；出銃需原本九面聽。');
      }
    }
    if (limits.isNotEmpty) return [limits.first];
  }
  if (suits.length == 1) {
    add(
      honors ? 'halfFlush' : 'fullFlush',
      honors ? (hk ? 3 : 4) : (hk ? 7 : 8),
      '檢查全副手牌與副露的花色。',
    );
  }
  if (!hk && suits.isEmpty) add('allHonors', 16, '全部為字牌。', label: '字一色');
  if (triplets.length == r.groupCount) {
    add('allPungs', hk ? 3 : 4, '全部組合均為刻子或槓。');
  }
  if (dragonCount == 3) add('bigDragons', hk ? 5 : 8, '中、發、白三組刻／槓。');
  if (dragonCount == 2 && d.pair >= 31) {
    add('smallDragons', hk ? 3 : 4, '兩組三元刻／槓，加另一三元作眼。');
  }
  if (hk || !(dragonCount == 3 || (dragonCount == 2 && d.pair >= 31))) {
    for (final t in ts.where((t) => t >= 31)) {
      add('dragon', 1, '${tileLabels[t]}刻／槓。', label: '${tileLabels[t]}三元牌');
    }
  }
  if (ts.contains(27 + h.seatWind)) {
    add('seatWind', 1, '門風${tileLabels[27 + h.seatWind]}刻／槓。');
  }
  if (ts.contains(27 + h.roundWind)) {
    add('roundWind', 1, '圈風${tileLabels[27 + h.roundWind]}刻／槓。');
  }
  if (hk && all.every((t) => isTerminal(t) || isHonor(t))) {
    add('mixedTerminals', 1, '只有么九與字牌，另計對對糊。');
  }
  final waiting = hk ? <int>{} : _waits(h, r);
  if (triplets.isEmpty &&
      (hk ||
          (!honors &&
              h.flowers.isEmpty &&
              !h.selfDraw &&
              waiting.length > 1 &&
              role == _WinningRole.chow))) {
    add('chows', hk ? 1 : 2, hk ? '四組順子，眼不限。' : '五組順子，無字無花，非獨聽出銃且食糊牌完成順子。');
  }
  if (hk) {
    if (h.selfDraw) add('selfDraw', 1, '自己摸入食糊牌。');
    if (!r.flowers && h.melds.isEmpty) add('closed', 1, '無花牌例，未吃碰槓。');
  } else {
    if (closed && h.selfDraw) {
      add('closedSelfDraw', 3, '門清、自摸及不求合計三台。');
    } else {
      if (closed) add('closed', 1, '沒有吃、碰或明槓。');
      if (h.selfDraw) add('selfDraw', 1, '自己摸入食糊牌。');
    }
    if (concealedTriplets >= 3) {
      add(
        ['threeConcealed', 'fourConcealed', 'fiveConcealed'][concealedTriplets -
            3],
        [2, 5, 8][concealedTriplets - 3],
        '暗槓算暗刻；出銃完成的刻子不算暗刻。',
      );
    }
    if (h.melds.length == 5 && h.melds.every((m) => m.isOpen) && !h.selfDraw) {
      add('allExposed', 2, '五組副露，出銃完成眼；此家規不再加獨聽。');
    } else if (waiting.length == 1) {
      add('singleWait', 1, '移去食糊牌後只有一種結構上可食糊的牌。');
    }
    if (windCount == 4) add('bigWinds', 16, '四組風牌。', label: '大四喜');
    if (windCount == 3 && d.pair >= 27 && d.pair <= 30) {
      add('smallWinds', 8, '三風刻與另一風眼。', label: '小四喜');
    }
  }
  if (r.flowers) {
    if (hk && h.flowers.isEmpty) add('noFlowers', 1, '有花牌規則，但本手沒有花。');
    for (final f in h.flowers.where((f) => (f - 34) % 4 == h.seatWind)) {
      add('seatFlower', 1, '${tileLabels[f]}號碼對應門風；以實物編號為準。');
    }
    for (final start in [34, 38]) {
      if (List.generate(4, (i) => start + i).every(h.flowers.contains)) {
        add('flowerSet', hk ? 1 : 2, '同一組四張花牌齊全。');
      }
    }
  }
  if (h.robbed) add('robKong', 1, '食他家加槓牌；與自摸分開判定。');
  if (h.replacement == Replacement.kong ||
      (!hk && h.replacement == Replacement.flower)) {
    add('kongWin', 1, '補牌後直接食糊。');
  }
  if (h.lastTile == LastTile.draw) add('lastDraw', 1, '最後可摸牌自摸。');
  return p;
}

Set<int> _waits(Hand h, Rules r) {
  final before = h.concealed.toList();
  before.remove(h.winningTile);
  final counts = List.filled(34, 0);
  for (final t in [...before, ...h.melds.expand((m) => m.tiles)]) {
    counts[t]++;
  }
  return {
    for (var t = 0; t < 34; t++)
      if (counts[t] < 4 &&
          decompose([...before, t], r.groupCount - h.melds.length).isNotEmpty)
        t,
  };
}

/// Called only with a validated context by scoreHand. Exposed separately for
/// independently sourced settlement fixtures and arithmetic boundary tests.
List<Transfer> settle(Hand h, Rules r, int score) {
  if (validateRules(r).isNotEmpty ||
      score < r.minimum ||
      score > r.cap ||
      h.source == null ||
      [h.winner, h.discarder, h.dealer].any((p) => p < 0 || p > 3) ||
      (!h.selfDraw && h.winner == h.discarder) ||
      h.continuations < 0 ||
      h.continuations > 100 ||
      (r.family == RuleFamily.taiwanese && h.liablePlayer != null) ||
      (h.liablePlayer != null &&
          (h.liablePlayer! < 0 ||
              h.liablePlayer! > 3 ||
              h.liablePlayer == h.winner))) {
    throw ArgumentError('Invalid settlement input');
  }
  final opponents = List.generate(
    4,
    (i) => i,
  ).where((i) => i != h.winner).toList();
  final hk = r.family == RuleFamily.hongKong;
  // Adopted Chinese HKMA summary rule 14 exempts a direct kong-replacement
  // self-draw from bao. A prior kong or a flower replacement is not enough;
  // Robbing another player's kong has a separate payer rule.
  final responsibilityApplies =
      hk &&
      h.selfDraw &&
      h.replacement != Replacement.kong &&
      h.liablePlayer != null;
  final amounts = <int, int>{};
  if (hk) {
    final value = hkDiscardTable[score]! * r.unit;
    if (!h.selfDraw && !h.robbed) {
      amounts[h.discarder] = value;
    } else if (r.payment == PaymentMode.splitTotal) {
      // Allocate integer remainder clockwise after winner, preserving total.
      for (var i = 1; i <= 3; i++) {
        amounts[(h.winner + i) % 4] = value ~/ 3 + (i <= value % 3 ? 1 : 0);
      }
    } else {
      for (final o in opponents) {
        amounts[o] = r.payment == PaymentMode.fullEach ? value : value ~/ 2;
      }
    }
    if (h.robbed) {
      // Robbing a kong pays the selected self-draw total, including house
      // full-each or split-total policies, entirely from the kong player.
      final total = amounts.values.fold(0, (sum, amount) => sum + amount);
      amounts.clear();
      amounts[h.discarder] = total;
    }
  } else {
    final payers = h.selfDraw ? opponents : [h.discarder];
    for (final o in payers) {
      final dealerTai = (h.winner == h.dealer || o == h.dealer)
          ? 1 + 2 * h.continuations
          : 0;
      amounts[o] = r.base + math.min(score + dealerTai, r.cap) * r.unit;
    }
    if (h.selfDraw && r.payment == PaymentMode.splitTotal) {
      // Fixed-total house option has no payer-dependent dealer adjustment.
      final value =
          r.base +
          math.min(
                score + (h.winner == h.dealer ? 1 + 2 * h.continuations : 0),
                r.cap,
              ) *
              r.unit;
      for (var i = 1; i <= 3; i++) {
        amounts[(h.winner + i) % 4] = value ~/ 3 + (i <= value % 3 ? 1 : 0);
      }
    }
  }
  if (responsibilityApplies) {
    final sum = amounts.values.fold(0, (a, b) => a + b);
    amounts.clear();
    amounts[h.liablePlayer!] = sum;
  }
  return amounts.entries
      .map(
        (e) => Transfer(
          e.key,
          h.winner,
          e.value,
          h.robbed
              ? '搶槓結算'
              : responsibilityApplies && h.liablePlayer == e.key
              ? '包牌'
              : h.selfDraw
              ? '自摸'
              : '出銃',
        ),
      )
      .toList();
}
