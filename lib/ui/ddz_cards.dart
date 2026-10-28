import 'package:flutter/material.dart';
import 'dart:math' as math;

String ddzCardLabel(int card) {
  if (card < 0) return '未公开的底牌';
  if (card >= 52) return card == 52 ? '小王' : '大王';
  const suits = ['黑桃', '红桃', '梅花', '方块'];
  const ranks = [
    'A',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'J',
    'Q',
    'K',
  ];
  return '${suits[card ~/ 13]}${ranks[card % 13]}';
}

class DdzCardFace extends StatelessWidget {
  const DdzCardFace({super.key, required this.card, this.selected = false});
  final int card;
  final bool selected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final font = math
          .min(c.maxWidth * .28, c.maxHeight * .23)
          .clamp(9.0, 23.0);
      final red = card == 53 || (card >= 0 && card < 52 && (card ~/ 13).isOdd);
      final color = red ? const Color(0xFFBD473B) : const Color(0xFF253F3B);
      const ranks = [
        'A',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        'J',
        'Q',
        'K',
      ];
      final label = card < 0
          ? ''
          : card >= 52
          ? card == 52
                ? '小'
                : '大'
          : ranks[card % 13];
      return ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: card < 0
                ? const Color(0xFF356E84)
                : selected
                ? const Color(0xFFFFE5A2)
                : const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE8A735)
                  : const Color(0xFFDACBAE),
              width: selected ? 2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: card < 0
              ? Center(
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    color: const Color(0xFFE5D4A2),
                    size: c.maxWidth * .5,
                  ),
                )
              : Stack(
                  children: [
                    Positioned(
                      top: 2,
                      left: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: font,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (card >= 52)
                            Text(
                              '王',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: font * .80,
                                height: 1,
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          else
                            CustomPaint(
                              size: Size(font * .85, font),
                              painter: _SuitPainter(card ~/ 13, color),
                            ),
                        ],
                      ),
                    ),
                    if (c.maxWidth > 40)
                      Positioned(
                        right: 5,
                        bottom: 6,
                        child: card >= 52
                            ? Icon(
                                Icons.auto_awesome_rounded,
                                color: color.withValues(alpha: .7),
                                size: font * 1.3,
                              )
                            : CustomPaint(
                                size: Size(font * 1.1, font * 1.3),
                                painter: _SuitPainter(
                                  card ~/ 13,
                                  color.withValues(alpha: .8),
                                ),
                              ),
                      ),
                  ],
                ),
        ),
      );
    },
  );
}

// Suit painter adapted from the Kimi K2.6 frontend draft.
class _SuitPainter extends CustomPainter {
  final int suit;
  final Color color;

  _SuitPainter(this.suit, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.35;

    switch (suit) {
      case 0: // spade
        _drawSpade(canvas, c, r, paint);
        break;
      case 1: // heart
        _drawHeart(canvas, c, r, paint);
        break;
      case 2: // club
        _drawClub(canvas, c, r, paint);
        break;
      case 3: // diamond
        _drawDiamond(canvas, c, r, paint);
        break;
    }
  }

  void _drawSpade(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..cubicTo(
        c.dx + r,
        c.dy - r * 0.3,
        c.dx + r * 0.5,
        c.dy + r * 0.5,
        c.dx,
        c.dy + r * 0.2,
      )
      ..cubicTo(
        c.dx - r * 0.5,
        c.dy + r * 0.5,
        c.dx - r,
        c.dy - r * 0.3,
        c.dx,
        c.dy - r,
      )
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(c.dx, c.dy + r * 0.2),
      Offset(c.dx, c.dy + r * 0.9),
      paint..strokeWidth = r * 0.25,
    );
  }

  void _drawHeart(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + r * 0.8)
      ..cubicTo(
        c.dx - r * 1.2,
        c.dy - r * 0.2,
        c.dx - r,
        c.dy - r,
        c.dx - r * 0.3,
        c.dy - r * 0.5,
      )
      ..cubicTo(
        c.dx - r * 0.1,
        c.dy - r * 0.8,
        c.dx,
        c.dy - r * 0.3,
        c.dx,
        c.dy - r * 0.3,
      )
      ..cubicTo(
        c.dx,
        c.dy - r * 0.3,
        c.dx + r * 0.1,
        c.dy - r * 0.8,
        c.dx + r * 0.3,
        c.dy - r * 0.5,
      )
      ..cubicTo(
        c.dx + r,
        c.dy - r,
        c.dx + r * 1.2,
        c.dy - r * 0.2,
        c.dx,
        c.dy + r * 0.8,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawClub(Canvas canvas, Offset c, double r, Paint paint) {
    for (final offset in [
      Offset(-r * 0.5, -r * 0.3),
      Offset(r * 0.5, -r * 0.3),
      Offset(0, -r * 0.8),
    ]) {
      canvas.drawCircle(c + offset, r * 0.35, paint);
    }
    canvas.drawLine(
      Offset(c.dx, c.dy + r * 0.1),
      Offset(c.dx, c.dy + r * 0.9),
      paint..strokeWidth = r * 0.2,
    );
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.7, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.7, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
