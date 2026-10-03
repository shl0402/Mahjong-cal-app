import 'package:flutter/material.dart';

import '../main.dart' show heading, section, gap, dropdown, pine;
import '../domain/scoring.dart';

class SettingsPage extends StatefulWidget {
  final Rules rules;
  final Future<void> Function(Rules) onChanged;
  const SettingsPage({super.key, required this.rules, required this.onChanged});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Rules get rules => widget.rules;
  Future<void> apply(Rules r) async {
    final validKeys = defaultPatternValues(r).keys;
    await widget.onChanged(
      r.copyWith(
        overrides: Map.fromEntries(
          r.overrides.entries.where((e) => validKeys.contains(e.key)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
    children: [
      heading(
        context,
        'YOUR HOUSE RULES',
        '你們的牌局，\n你們的規則。',
        '先選牌例，再微調。支付方式與牌型分數分開設定。',
      ),
      section(
        '目前可試用',
        Column(
          children: [
            RadioGroup<RuleFamily>(
              groupValue: rules.family,
              onChanged: (v) =>
                  apply(v == RuleFamily.hongKong ? Rules() : Rules.taiwanese()),
              child: Column(
                children: [
                  for (final f in RuleFamily.values)
                    RadioListTile<RuleFamily>(
                      contentPadding: EdgeInsets.zero,
                      value: f,
                      title: Text(
                        f == RuleFamily.hongKong
                            ? '香港牌 · 13 張'
                            : '台灣牌 · 16 張家規',
                      ),
                      subtitle: Text(
                        f == RuleFamily.hongKong
                            ? '協會牌型基礎，3 番起糊，10 番封頂'
                            : '基本牌型與底台制，並非所有台灣玩法',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '測試版：七／八花即時花糊、台灣天聽地聽與天胡地胡、槓牌即時收付、多人同時食糊等情況，尚未完整支援。請勿將結果當作這些玩法的結算。',
                style: TextStyle(
                  color: Color(0xff956329),
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      ),
      gap,
      section(
        '起糊與上限',
        Column(
          children: [
            number(
              '起糊番／台',
              rules.minimum,
              (v) => apply(rules.copyWith(minimum: v)),
            ),
            number('番／台上限', rules.cap, (v) => apply(rules.copyWith(cap: v))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('使用花牌'),
              value: rules.flowers,
              onChanged: (v) => apply(rules.copyWith(flowers: v)),
            ),
          ],
        ),
      ),
      gap,
      section(
        '支付方式',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rules.family == RuleFamily.taiwanese)
              number('每底', rules.base, (v) => apply(rules.copyWith(base: v))),
            number(
              rules.family == RuleFamily.hongKong ? '換算單位（表中分數 × 單位）' : '每台',
              rules.unit,
              (v) => apply(rules.copyWith(unit: v)),
            ),
            gap,
            dropdown<PaymentMode>('自摸如何支付', rules.payment, {
              PaymentMode.preset: rules.family == RuleFamily.hongKong
                  ? '每人支付出銃額的一半'
                  : '每人各付一份底＋台',
              if (rules.family == RuleFamily.hongKong)
                PaymentMode.fullEach: '每人支付完整出銃額',
              PaymentMode.splitTotal: '一份總額由三家分攤（自訂）',
            }, (v) => apply(rules.copyWith(payment: v))),
            gap,
            paymentPreview(),
            if (rules.family == RuleFamily.taiwanese)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '莊家相關支付加 1＋2×連莊次數台；上限包括莊家台。分攤模式只計食糊者的莊家加台。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xff66746C),
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
      gap,
      section(
        '自訂番種',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '調整已支援番種的分值；填 0 可停用。香港例牌及特殊規則需另行實作。',
              style: TextStyle(
                color: Color(0xff66746C),
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in rules.overrides.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(patternNames[entry.key] ?? entry.key),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${entry.value}'),
                    IconButton(
                      tooltip: '恢復預設分值',
                      onPressed: () => apply(
                        rules.copyWith(
                          overrides: Map<String, int>.of(rules.overrides)
                            ..remove(entry.key),
                        ),
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: editPattern,
              icon: const Icon(Icons.add),
              label: const Text('調整番種分值'),
            ),
          ],
        ),
      ),
      gap,
      section(
        '更多牌例',
        const Text(
          '日麻四人／三人、國標 MCR、競技中庸、香港 16 張、新加坡、四川血戰／血流、廣東推倒胡／雞平胡、馬來西亞三人與美式牌。\n\n已列入研究及擴充計畫；尚未開放計算，避免以不完整規則給出錯誤結果。',
          style: TextStyle(color: Color(0xff66746C), height: 1.7),
        ),
      ),
      gap,
      section(
        '關於這個版本',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '0.2 · 即時掃描測試版\n相機畫面只在裝置內處理。確認後仍可修改；花牌需手動加入。\n香港牌依香港麻雀協會牌例研究；台灣預設為基本家規，並非完整官方牌例。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xff66746C),
                height: 1.7,
              ),
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: '牌照 · Mahjong Vision',
                applicationVersion: '0.2.0',
              ),
              child: const Text('開源授權'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget number(String title, int value, void Function(int) accept) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 14)),
    trailing: TextButton(
      onPressed: () async {
        final result = await showDialog<int>(
          context: context,
          builder: (c) => _NumberDialog(title: title, initial: value),
        );
        if (result != null) accept(result);
      },
      child: Text(
        '$value',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ),
  );
  Widget paymentPreview() {
    final score = rules.family == RuleFamily.hongKong
        ? rules.minimum
        : 3.clamp(rules.minimum, rules.cap);
    final payments = settle(Hand(source: WinSource.selfDraw), rules, score);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffEEF3EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '例：莊家 A 自摸 $score ${rules.family == RuleFamily.hongKong ? '番' : '台'}\n${payments.map((t) => '玩家 ${String.fromCharCode(65 + t.from)} 付 ${t.amount}').join('　')}\n合計收取 ${payments.fold<int>(0, (n, t) => n + t.amount)}',
        style: const TextStyle(color: pine, fontSize: 12, height: 1.8),
      ),
    );
  }

  Future<void> editPattern() async {
    final defaults = defaultPatternValues(rules);
    var key = defaults.keys.first;
    var value = rules.overrides[key] ?? defaults[key]!;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('自訂番種分值'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dropdown<String>(
                '番種',
                key,
                {for (final id in defaults.keys) id: patternNames[id] ?? id},
                (v) => refresh(() {
                  key = v;
                  value = rules.overrides[v] ?? defaults[v]!;
                }),
              ),
              gap,
              TextFormField(
                key: ValueKey(key),
                initialValue: '$value',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '分值（0–100）',
                  errorText: error,
                ),
                onChanged: (v) => value = int.tryParse(v) ?? -1,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (value < 0 || value > 100) {
                  refresh(() => error = '請輸入 0–100 的整數');
                  return;
                }
                apply(
                  rules.copyWith(overrides: {...rules.overrides, key: value}),
                );
                Navigator.pop(ctx);
              },
              child: const Text('套用'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberDialog extends StatefulWidget {
  final String title;
  final int initial;
  const _NumberDialog({required this.title, required this.initial});
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final controller = TextEditingController(text: '${widget.initial}');
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: '整數數值', errorText: error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final n = int.tryParse(controller.text);
          if (n == null || n < 0) {
            setState(() => error = '請輸入非負整數');
            return;
          }
          Navigator.pop(context, n);
        },
        child: const Text('套用'),
      ),
    ],
  );
}
