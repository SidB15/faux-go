import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Cached paint objects to avoid recreation on every frame
class _PaintCache {
  static final Paint backgroundPaint = Paint()..color = AppTheme.boardBackground;

  static final Paint linePaint = Paint()
    ..color = AppTheme.gridLine
    ..strokeWidth = 1.0;

  static final Paint accentPaint = Paint()
    ..color = AppTheme.gridLineAccent
    ..strokeWidth = 1.5;

  static final Paint starPointPaint = Paint()
    ..color = AppTheme.gridLineAccent
    ..style = PaintingStyle.fill;

  // Stone paints - shadow uses simple offset instead of expensive blur
  static final Paint shadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.25);

  static final Paint blackStoneFill = Paint()
    ..color = AppTheme.blackStone
    ..style = PaintingStyle.fill;

  static final Paint whiteStoneFill = Paint()
    ..color = AppTheme.whiteStone
    ..style = PaintingStyle.fill;

  static final Paint blackStoneBorder = Paint()
    ..color = AppTheme.blackStoneBorder
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  static final Paint whiteStoneBorder = Paint()
    ..color = AppTheme.whiteStoneBorder
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  static final Paint whiteHighlight = Paint()
    ..color = Colors.white.withOpacity(0.4)
    ..style = PaintingStyle.fill;

  static final Paint blackHighlight = Paint()
    ..color = Colors.white.withOpacity(0.15)
    ..style = PaintingStyle.fill;

  static final Paint lastMoveWhite = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint lastMoveBlack = Paint()
    ..color = AppTheme.lastMoveHighlight
    ..style = PaintingStyle.fill;

  // Enclosure (fort) line paints
  static final Paint blackEnclosurePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..strokeWidth = 3.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint whiteEnclosurePaint = Paint()
    ..color = const Color(0xFFE0E0E0)
    ..strokeWidth = 3.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // Glow effect for enclosures
  static final Paint blackEnclosureGlow = Paint()
    ..color = Colors.black.withOpacity(0.3)
    ..strokeWidth = 6.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint whiteEnclosureGlow = Paint()
    ..color = Colors.grey.withOpacity(0.3)
    ..strokeWidth = 6.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
}

class BoardPainter extends CustomPainter {
  final Board board;
  final Position? lastMove;
  final double cellSize;
  final List<Enclosure> enclosures;

  BoardPainter({
    required this.board,
    this.lastMove,
    required this.cellSize,
    this.enclosures = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGridLines(canvas, size);
    _drawStarPoints(canvas, size);
    _drawEnclosures(canvas);
    _drawStones(canvas);
    if (lastMove != null) {
      _drawLastMoveHighlight(canvas);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _PaintCache.backgroundPaint);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    // Draw vertical lines
    for (int i = 0; i < board.size; i++) {
      final x = i * cellSize + cellSize / 2;
      final isAccent = i % 6 == 0;
      canvas.drawLine(
        Offset(x, cellSize / 2),
        Offset(x, (board.size - 1) * cellSize + cellSize / 2),
        isAccent ? _PaintCache.accentPaint : _PaintCache.linePaint,
      );
    }

    // Draw horizontal lines
    for (int i = 0; i < board.size; i++) {
      final y = i * cellSize + cellSize / 2;
      final isAccent = i % 6 == 0;
      canvas.drawLine(
        Offset(cellSize / 2, y),
        Offset((board.size - 1) * cellSize + cellSize / 2, y),
        isAccent ? _PaintCache.accentPaint : _PaintCache.linePaint,
      );
    }
  }

  void _drawStarPoints(Canvas canvas, Size size) {
    // Star points at every 12 intersections (and corners at 6, 42)
    // Add star points at 6, 24, 42 positions
    for (int x in [6, 24, 42]) {
      for (int y in [6, 24, 42]) {
        if (x < board.size && y < board.size) {
          final px = x * cellSize + cellSize / 2;
          final py = y * cellSize + cellSize / 2;
          canvas.drawCircle(Offset(px, py), cellSize * 0.12, _PaintCache.starPointPaint);
        }
      }
    }
  }

  void _drawEnclosures(Canvas canvas) {
    for (final enclosure in enclosures) {
      _drawEnclosure(canvas, enclosure);
    }
  }

  void _drawEnclosure(Canvas canvas, Enclosure enclosure) {
    final edges = enclosure.wallEdges;
    if (edges.isEmpty) return;

    final isBlack = enclosure.owner == StoneColor.black;
    final glowPaint = isBlack ? _PaintCache.blackEnclosureGlow : _PaintCache.whiteEnclosureGlow;
    final linePaint = isBlack ? _PaintCache.blackEnclosurePaint : _PaintCache.whiteEnclosurePaint;

    // Draw glow first (behind the main line)
    for (final edge in edges) {
      final x1 = edge.$1.x * cellSize + cellSize / 2;
      final y1 = edge.$1.y * cellSize + cellSize / 2;
      final x2 = edge.$2.x * cellSize + cellSize / 2;
      final y2 = edge.$2.y * cellSize + cellSize / 2;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), glowPaint);
    }

    // Draw main lines
    for (final edge in edges) {
      final x1 = edge.$1.x * cellSize + cellSize / 2;
      final y1 = edge.$1.y * cellSize + cellSize / 2;
      final x2 = edge.$2.x * cellSize + cellSize / 2;
      final y2 = edge.$2.y * cellSize + cellSize / 2;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
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

    // Draw shadow (simple offset, no expensive blur filter)
    canvas.drawCircle(Offset(x + 2, y + 2), radius, _PaintCache.shadowPaint);

    // Draw stone fill and border using cached paints
    if (color == StoneColor.black) {
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.blackStoneFill);
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.blackStoneBorder);
      // Subtle highlight
      canvas.drawCircle(
        Offset(x - radius * 0.3, y - radius * 0.3),
        radius * 0.2,
        _PaintCache.blackHighlight,
      );
    } else {
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.whiteStoneFill);
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.whiteStoneBorder);
      // Subtle highlight
      canvas.drawCircle(
        Offset(x - radius * 0.3, y - radius * 0.3),
        radius * 0.25,
        _PaintCache.whiteHighlight,
      );
    }
  }

  void _drawLastMoveHighlight(Canvas canvas) {
    if (lastMove == null) return;

    final x = lastMove!.x * cellSize + cellSize / 2;
    final y = lastMove!.y * cellSize + cellSize / 2;
    final radius = cellSize * 0.15;

    final stone = board.getStoneAt(lastMove!);
    final paint = stone == StoneColor.black
        ? _PaintCache.lastMoveWhite
        : _PaintCache.lastMoveBlack;

    canvas.drawCircle(Offset(x, y), radius, paint);
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    return oldDelegate.board != board ||
        oldDelegate.lastMove != lastMove ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.enclosures.length != enclosures.length;
  }
}
