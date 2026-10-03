/// Canonical order: man, pin, sou, east/south/west/north/white/green/red,
/// then four seasons and four numbered flowers. Never use model class IDs here.
const tileLabels = [
  '一萬',
  '二萬',
  '三萬',
  '四萬',
  '五萬',
  '六萬',
  '七萬',
  '八萬',
  '九萬',
  '一筒',
  '二筒',
  '三筒',
  '四筒',
  '五筒',
  '六筒',
  '七筒',
  '八筒',
  '九筒',
  '一索',
  '二索',
  '三索',
  '四索',
  '五索',
  '六索',
  '七索',
  '八索',
  '九索',
  '東',
  '南',
  '西',
  '北',
  '白',
  '發',
  '中',
  '春①',
  '夏②',
  '秋③',
  '冬④',
  '梅①',
  '蘭②',
  '菊③',
  '竹④',
];

String tileCode(int t) {
  RangeError.checkValueInInterval(t, 0, 41, 'tile');
  return t < 27
      ? '${t % 9 + 1}${['m', 'p', 's'][t ~/ 9]}'
      : t < 34
      ? '${t - 26}z'
      : '${t - 33}f';
}

List<int> parseTiles(String input) {
  final clean = input.replaceAll(RegExp(r'\s+'), '');
  final matches = RegExp(r'([1-9]+)([mpszf])').allMatches(clean).toList();
  if (matches.map((m) => m.group(0)).join() != clean) {
    throw const FormatException('Use notation such as 123m456p789s11122z.');
  }
  final out = <int>[];
  for (final m in matches) {
    final suit = m.group(2)!;
    for (final char in m.group(1)!.split('')) {
      final n = int.parse(char);
      if ((suit == 'z' && n > 7) || (suit == 'f' && n > 8)) {
        throw const FormatException('Tile rank out of range.');
      }
      out.add(
        suit == 'f'
            ? 33 + n
            : suit == 'z'
            ? 26 + n
            : ['m', 'p', 's'].indexOf(suit) * 9 + n - 1,
      );
    }
  }
  return out;
}

bool isHonor(int t) => t >= 27 && t < 34;
bool isTerminal(int t) => t >= 0 && t < 27 && (t % 9 == 0 || t % 9 == 8);

enum MeldKind { chow, pung, openKong, closedKong, addedKong }

class Meld {
  final MeldKind kind;
  final List<int> tiles;
  Meld(this.kind, Iterable<int> tiles) : tiles = List.unmodifiable(tiles);
  bool get isKong => kind.index >= MeldKind.openKong.index;
  bool get isOpen => kind != MeldKind.closedKong;
  bool get isTriplet => kind != MeldKind.chow;
  Map<String, dynamic> toJson() => {'kind': kind.name, 'tiles': tiles};
  factory Meld.fromJson(Map<String, dynamic> j) => Meld(
    MeldKind.values.byName(j['kind'] as String),
    (j['tiles'] as List).cast<int>(),
  );
}

class Decomposition {
  final int pair;
  final List<Meld> groups;
  Decomposition(this.pair, Iterable<Meld> groups)
    : groups = List.unmodifiable(groups);
}

/// Exhaustive partitioning, not a greedy first-match algorithm.
List<Decomposition> decompose(List<int> tiles, int groupCount) {
  if (groupCount < 0 ||
      tiles.length != groupCount * 3 + 2 ||
      tiles.any((t) => t < 0 || t >= 34)) {
    return [];
  }
  final counts = List.filled(34, 0);
  for (final t in tiles) {
    counts[t]++;
  }
  if (counts.any((n) => n > 4)) return [];
  final result = <Decomposition>[];
  void visit(int pair, List<Meld> groups) {
    final t = counts.indexWhere((n) => n > 0);
    if (t == -1) {
      if (groups.length == groupCount) result.add(Decomposition(pair, groups));
      return;
    }
    if (groups.length >= groupCount) return;
    if (counts[t] >= 3) {
      counts[t] -= 3;
      visit(pair, [
        ...groups,
        Meld(MeldKind.pung, [t, t, t]),
      ]);
      counts[t] += 3;
    }
    if (t < 27 && t % 9 <= 6 && counts[t + 1] > 0 && counts[t + 2] > 0) {
      for (final n in [t, t + 1, t + 2]) {
        counts[n]--;
      }
      visit(pair, [
        ...groups,
        Meld(MeldKind.chow, [t, t + 1, t + 2]),
      ]);
      for (final n in [t, t + 1, t + 2]) {
        counts[n]++;
      }
    }
  }

  for (var pair = 0; pair < 34; pair++) {
    if (counts[pair] < 2) continue;
    counts[pair] -= 2;
    visit(pair, []);
    counts[pair] += 2;
  }
  return result;
}

const orphanTiles = {0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33};
bool isThirteenOrphans(List<int> tiles) =>
    tiles.length == 14 &&
    tiles.every(orphanTiles.contains) &&
    tiles.toSet().containsAll(orphanTiles);
