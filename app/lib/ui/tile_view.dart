import 'package:flutter/material.dart';

import '../domain/tiles.dart';

class TileView extends StatelessWidget {
  final int tile;
  final bool selected, compact;
  final VoidCallback? onTap, onLongPress;
  const TileView({
    super.key,
    required this.tile,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final color = tile < 9 || tile == 33
        ? const Color(0xffB2473F)
        : tile < 18 || tile == 31
        ? const Color(0xff234D69)
        : const Color(0xff24614A);
    return Semantics(
      label: '${tileLabels[tile]}${selected ? '，食糊牌' : ''}',
      button: onTap != null,
      selected: selected,
      child: Tooltip(
        message: '${tileLabels[tile]}${selected ? ' · 食糊牌' : ''}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              width: compact ? 35 : 43,
              height: compact ? 49 : 60,
              decoration: BoxDecoration(
                color: const Color(0xffFFFEF8),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? const Color(0xffB68335)
                      : const Color(0xffD5DBD2),
                  width: selected ? 2 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12194D40),
                    offset: Offset(0, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(3, 3, 3, 4),
              child: Column(
                children: [
                  Expanded(
                    child: tile < 27
                        ? CustomPaint(
                            size: Size.infinite,
                            painter: _TilePainter(tile, color),
                          )
                        : Center(
                            child: Text(
                              tileLabels[tile],
                              style: TextStyle(
                                color: color,
                                fontSize: compact ? 24 : 30,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                  if (tile < 27)
                    Text(
                      tileLabels[tile],
                      style: TextStyle(
                        color: color,
                        fontSize: compact ? 8 : 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  final int tile;
  final Color color;
  const _TilePainter(this.tile, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final n = tile % 9 + 1;
    if (tile < 9) {
      final text = TextPainter(
        text: TextSpan(
          text: '${['一', '二', '三', '四', '五', '六', '七', '八', '九'][n - 1]}\n萬',
          style: TextStyle(
            fontSize: size.height * .44,
            height: 1,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
      return;
    }
    final points = <Offset>[];
    if (n == 1) {
      points.add(Offset(size.width / 2, size.height / 2));
    } else if (n <= 3) {
      for (var i = 0; i < n; i++) {
        points.add(Offset(size.width / 2, size.height * (i + 1) / (n + 1)));
      }
    } else {
      final columns = n > 6 ? 3 : 2, rows = (n / columns).ceil();
      for (var i = 0; i < n; i++) {
        points.add(
          Offset(
            size.width * ((i % columns) + 1) / (columns + 1),
            size.height * ((i ~/ columns) + 1) / (rows + 1),
          ),
        );
      }
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final paint = Paint()
        ..color = (n == 5 && i == 2) ? const Color(0xffB2473F) : color;
      if (tile < 18) {
        final radius = n == 1 ? size.width * .26 : 3.1;
        canvas.drawCircle(
          p,
          radius,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(p, radius * .37, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: p, width: 3.2, height: n == 1 ? 19 : 7),
            const Radius.circular(1),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(p.dx - 2, p.dy),
          Offset(p.dx + 2, p.dy),
          Paint()
            ..color = const Color(0xffE4EDE2)
            ..strokeWidth = .8,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TilePainter oldDelegate) =>
      tile != oldDelegate.tile || color != oldDelegate.color;
}

class TilePalette extends StatelessWidget {
  final ValueChanged<int> onSelected;
  final bool Function(int)? enabled;
  const TilePalette({super.key, required this.onSelected, this.enabled});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, c) => Column(
      children: [
        for (final start in [0, 9, 18, 27])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var t = start; t < (start == 27 ? 34 : start + 9); t++)
                  Expanded(
                    child: Opacity(
                      opacity: enabled?.call(t) == false ? .25 : 1,
                      child: Center(
                        child: TileView(
                          tile: t,
                          compact: c.maxWidth < 420,
                          onTap: enabled?.call(t) == false
                              ? null
                              : () => onSelected(t),
                        ),
                      ),
                    ),
                  ),
                if (start == 27) ...[const Spacer(), const Spacer()],
              ],
            ),
          ),
      ],
    ),
  );
}
