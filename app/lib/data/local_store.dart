import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scoring.dart';

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freeze(item))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

class SavedHand {
  final String id, date;
  final Map<String, dynamic> hand, rules, result;
  SavedHand(
    this.id,
    this.date,
    Map<String, dynamic> hand,
    Map<String, dynamic> rules,
    Map<String, dynamic> result,
  ) : hand = _freeze(hand) as Map<String, dynamic>,
      rules = _freeze(rules) as Map<String, dynamic>,
      result = _freeze(result) as Map<String, dynamic> {
    _validate();
  }

  void _validate() {
    void require(bool valid) {
      if (!valid) throw const FormatException('Invalid saved hand');
    }

    require(
      id.isNotEmpty && date.length >= 16 && DateTime.tryParse(date) != null,
    );
    final savedRules = Rules.fromJson(rules);
    final savedHand = Hand.fromJson(hand);
    require(
      validateRules(savedRules).isEmpty &&
          validateHand(savedHand, savedRules).isEmpty,
    );
    require(
      savedHand.source != null &&
          savedHand.winningTile != null &&
          savedHand.circumstancesConfirmed,
    );
    require(
      result['engineVersion'] is String &&
          (result['engineVersion'] as String).isNotEmpty,
    );
    for (final key in ['score', 'rawScore', 'total']) {
      require(result[key] is int && result[key] >= 0);
    }
    require(result['score'] <= result['rawScore']);
    require(
      result['patterns'] is List &&
          result['transfers'] is List &&
          result['balances'] is List,
    );
    final balances = result['balances'] as List;
    require(balances.length == 4 && balances.every((v) => v is int));
    final computed = List<int>.filled(4, 0);
    var total = 0;
    for (final t in result['transfers'] as List) {
      require(
        t is Map &&
            t['from'] is int &&
            t['to'] is int &&
            t['amount'] is int &&
            t['reason'] is String,
      );
      final from = t['from'] as int,
          to = t['to'] as int,
          amount = t['amount'] as int;
      require(
        from >= 0 &&
            from < 4 &&
            to == savedHand.winner &&
            from != to &&
            amount >= 0,
      );
      computed[from] -= amount;
      computed[to] += amount;
      total += amount;
    }
    require(total == result['total']);
    require(
      List.generate(4, (i) => balances[i] == computed[i]).every((v) => v),
    );
    for (final p in result['patterns'] as List) {
      require(
        p is Map &&
            p['label'] is String &&
            p['reason'] is String &&
            p['value'] is int &&
            p['value'] >= 0,
      );
    }
    // Historical results retain their engine version; never recalculate here.
  }

  factory SavedHand.capture(Hand h, Rules r, ScoreResult s) {
    if (s.status != ResultStatus.valid) {
      throw ArgumentError('Only valid completed scores may be saved.');
    }
    final now = DateTime.now();
    return SavedHand(
      now.microsecondsSinceEpoch.toString(),
      now.toIso8601String(),
      h.toJson(),
      r.toJson(),
      {
        'score': s.score,
        'rawScore': s.rawScore,
        'total': s.total,
        'engineVersion': Rules.version,
        'balances': s.balances,
        'patterns': s.patterns
            .map(
              (p) => {'label': p.label, 'value': p.value, 'reason': p.reason},
            )
            .toList(),
        'transfers': s.transfers.map((t) => t.toJson()).toList(),
      },
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'hand': hand,
    'rules': rules,
    'result': result,
  };
  factory SavedHand.fromJson(Map<String, dynamic> j) => SavedHand(
    j['id'],
    j['date'],
    Map<String, dynamic>.from(j['hand']),
    Map<String, dynamic>.from(j['rules']),
    Map<String, dynamic>.from(j['result']),
  );
}

class LocalStore {
  final SharedPreferences prefs;
  LocalStore(this.prefs);
  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());
  String? warning;
  Object? _unreadableHistory;
  Rules readRules() {
    try {
      final raw = prefs.getString('rules.v1');
      if (raw == null) return Rules();
      final r = Rules.fromJson(jsonDecode(raw));
      if (validateRules(r).isNotEmpty) throw const FormatException();
      return r;
    } catch (_) {
      warning = '儲存的設定無法讀取，已使用預設規則。';
      return Rules();
    }
  }

  List<SavedHand> readHistory() {
    try {
      final entries = jsonDecode(prefs.getString('history.v1') ?? '[]') as List;
      final recovered = <SavedHand>[];
      for (final entry in entries) {
        try {
          recovered.add(SavedHand.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          _historyWarning();
        }
      }
      return recovered;
    } catch (_) {
      _historyWarning();
      return [];
    }
  }

  void _historyWarning() {
    _unreadableHistory = prefs.get('history.v1');
    warning = '部分牌局記錄無法讀取，原始資料仍保留在裝置。';
  }

  Future<void> saveRules(Rules r) async {
    if (!await prefs.setString('rules.v1', jsonEncode(r.toJson()))) {
      throw StateError('設定未能儲存。');
    }
  }

  Future<void> saveHistory(List<SavedHand> entries) async {
    // Preserve recovery bytes before a later save replaces a damaged payload.
    if (_unreadableHistory != null) {
      final backup =
          'history.v1.recovery.${DateTime.now().microsecondsSinceEpoch}';
      final original = _unreadableHistory;
      if (!await prefs.setString(
        backup,
        original is String ? original : jsonEncode(original),
      )) {
        throw StateError('未能備份原始牌局記錄。');
      }
      _unreadableHistory = null;
    }
    if (!await prefs.setString(
      'history.v1',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('記錄未能儲存。');
    }
  }
}
