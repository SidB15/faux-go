import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class BoardPainter extends CustomPainter {
  final Board board;
  final Position? lastMove;
  final double cellSize;

  BoardPainter({
    required this.board,
    this.lastMove,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGridLines(canvas, size);
    _drawStarPoints(canvas, size);
    _drawStones(canvas);
    if (lastMove != null) {
      _drawLastMoveHighlight(canvas);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = AppTheme.boardBackground;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppTheme.gridLine
      ..strokeWidth = 1.0;

    final accentPaint = Paint()
      ..color = AppTheme.gridLineAccent
      ..strokeWidth = 1.5;

    // Draw vertical lines
    for (int i = 0; i < board.size; i++) {
      final x = i * cellSize + cellSize / 2;
      final isAccent = i % 6 == 0;
      canvas.drawLine(
        Offset(x, cellSize / 2),
        Offset(x, (board.size - 1) * cellSize + cellSize / 2),
        isAccent ? accentPaint : linePaint,
      );
    }

    // Draw horizontal lines
    for (int i = 0; i < board.size; i++) {
      final y = i * cellSize + cellSize / 2;
      final isAccent = i % 6 == 0;
      canvas.drawLine(
        Offset(cellSize / 2, y),
        Offset((board.size - 1) * cellSize + cellSize / 2, y),
        isAccent ? accentPaint : linePaint,
      );
    }
  }

  void _drawStarPoints(Canvas canvas, Size size) {
    // Draw star points (dots at regular intervals for orientation)
    final paint = Paint()
      ..color = AppTheme.gridLineAccent
      ..style = PaintingStyle.fill;

    // Star points at every 12 intersections (and corners at 6, 42)
    final starPoints = <Position>[];

    // Add star points at 6, 24, 42 positions
    for (int x in [6, 24, 42]) {
      for (int y in [6, 24, 42]) {
        if (x < board.size && y < board.size) {
          starPoints.add(Position(x, y));
        }
      }
    }

    for (final point in starPoints) {
      final x = point.x * cellSize + cellSize / 2;
      final y = point.y * cellSize + cellSize / 2;
      canvas.drawCircle(Offset(x, y), cellSize * 0.12, paint);
    }
  }

  void _drawStones(Canvas canvas) {
    for (final entry in board.stones.entries) {
      _drawStone(canvas, entry.key, entry.value);
    }
  }

  void _drawStone(Canvas canvas, Position pos, StoneColor color) {
    final x = pos.x * cellSize + cellSize / 2;
    final y = pos.y * cellSize + cellSize / 2;
    final radius = cellSize * 0.42;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(x + 2, y + 2), radius, shadowPaint);

    // Draw stone fill
    final fillPaint = Paint()
      ..color = color == StoneColor.black
          ? AppTheme.blackStone
          : AppTheme.whiteStone
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), radius, fillPaint);

    // Draw stone border
    final borderPaint = Paint()
      ..color = color == StoneColor.black
          ? AppTheme.blackStoneBorder
          : AppTheme.whiteStoneBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(x, y), radius, borderPaint);

    // Draw subtle highlight (gradient effect)
    if (color == StoneColor.white) {
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.4)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(x - radius * 0.3, y - radius * 0.3),
        radius * 0.25,
        highlightPaint,
      );
    } else {
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(x - radius * 0.3, y - radius * 0.3),
        radius * 0.2,
        highlightPaint,
      );
    }
  }

  void _drawLastMoveHighlight(Canvas canvas) {
    if (lastMove == null) return;

    final x = lastMove!.x * cellSize + cellSize / 2;
    final y = lastMove!.y * cellSize + cellSize / 2;
    final radius = cellSize * 0.15;

    final stone = board.getStoneAt(lastMove!);
    final paint = Paint()
      ..color = stone == StoneColor.black
          ? Colors.white
          : AppTheme.lastMoveHighlight
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(x, y), radius, paint);
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    return oldDelegate.board != board ||
        oldDelegate.lastMove != lastMove ||
        oldDelegate.cellSize != cellSize;
  }
}
