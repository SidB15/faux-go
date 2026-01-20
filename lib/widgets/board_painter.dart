import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Cached paint objects to avoid recreation on every frame
class _PaintCache {
  static final Paint backgroundPaint = Paint()..color = AppTheme.boardBackground;

  // 3-tier grid line system (paints created dynamically based on zoom)
  static Paint createMicroGridPaint(double opacity) => Paint()
    ..color = AppTheme.gridLine.withValues(alpha: opacity)
    ..strokeWidth = 0.5;

  static Paint createMajorGridPaint(double opacity) => Paint()
    ..color = AppTheme.gridLineAccent.withValues(alpha: opacity)
    ..strokeWidth = 1.0;

  static final Paint boundaryPaint = Paint()
    ..color = AppTheme.gridLineBoundary
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

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

  // Ghost stones (captured pieces shown with transparency)
  static final Paint ghostBlackFill = Paint()
    ..color = AppTheme.blackStone.withValues(alpha: 0.25)
    ..style = PaintingStyle.fill;

  static final Paint ghostWhiteFill = Paint()
    ..color = AppTheme.whiteStone.withValues(alpha: 0.25)
    ..style = PaintingStyle.fill;

  static final Paint ghostBlackBorder = Paint()
    ..color = AppTheme.blackStoneBorder.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  static final Paint ghostWhiteBorder = Paint()
    ..color = AppTheme.whiteStoneBorder.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
}

class BoardPainter extends CustomPainter {
  final Board board;
  final Position? lastMove;
  final double cellSize;
  final List<Enclosure> enclosures;
  /// Positions of recently captured stones (for ghost display)
  final Set<Position> capturedPositions;
  /// Color of the captured stones (opponent of who made the capture)
  final StoneColor? capturedColor;
  /// Current zoom scale (1.0 = default, <1 = zoomed out, >1 = zoomed in)
  final double scale;

  BoardPainter({
    required this.board,
    this.lastMove,
    required this.cellSize,
    this.enclosures = const [],
    this.capturedPositions = const {},
    this.capturedColor,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawBoardBoundary(canvas, size);
    _drawGridLines(canvas, size);
    _drawStarPoints(canvas, size);
    _drawEnclosures(canvas);
    _drawGhostStones(canvas);
    _drawStones(canvas);
    if (lastMove != null) {
      _drawLastMoveHighlight(canvas);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _PaintCache.backgroundPaint);
  }

  void _drawBoardBoundary(Canvas canvas, Size size) {
    // Draw a clear boundary around the playing area
    final halfCell = cellSize / 2;
    final boardRect = Rect.fromLTRB(
      halfCell - 2,
      halfCell - 2,
      (board.size - 1) * cellSize + halfCell + 2,
      (board.size - 1) * cellSize + halfCell + 2,
    );
    canvas.drawRect(boardRect, _PaintCache.boundaryPaint);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    // Dynamic opacity based on zoom level
    // When zoomed out (scale < 1), fade micro grid more
    // When zoomed in (scale > 1), restore micro grid
    final microOpacity = (scale < 0.6)
        ? 0.25  // Very zoomed out: still somewhat visible
        : (scale < 1.0)
            ? 0.25 + (scale - 0.6) * 0.375  // Zoomed out: fade gradually
            : 0.4;  // Normal/zoomed in: clearly visible

    final majorOpacity = (scale < 0.5)
        ? 0.4  // Very zoomed out: reduced
        : 0.6;  // Normal: visible but not dominant

    final microPaint = _PaintCache.createMicroGridPaint(microOpacity);
    final majorPaint = _PaintCache.createMajorGridPaint(majorOpacity);

    final halfCell = cellSize / 2;
    final endPos = (board.size - 1) * cellSize + halfCell;

    // Draw vertical lines with 3-tier hierarchy
    for (int i = 0; i < board.size; i++) {
      final x = i * cellSize + halfCell;
      final isBoundary = i == 0 || i == board.size - 1;
      final isMajor = i % 6 == 0;

      // Skip boundary lines (handled by _drawBoardBoundary)
      if (isBoundary) continue;

      canvas.drawLine(
        Offset(x, halfCell),
        Offset(x, endPos),
        isMajor ? majorPaint : microPaint,
      );
    }

    // Draw horizontal lines with 3-tier hierarchy
    for (int i = 0; i < board.size; i++) {
      final y = i * cellSize + halfCell;
      final isBoundary = i == 0 || i == board.size - 1;
      final isMajor = i % 6 == 0;

      // Skip boundary lines (handled by _drawBoardBoundary)
      if (isBoundary) continue;

      canvas.drawLine(
        Offset(halfCell, y),
        Offset(endPos, y),
        isMajor ? majorPaint : microPaint,
      );
    }
  }

  void _drawStarPoints(Canvas canvas, Size size) {
    // Star points at strategic positions
    // Only draw if not too zoomed out (they'd be invisible anyway)
    if (scale < 0.4) return;

    final starPointOpacity = scale < 0.7 ? 0.3 : 0.6;
    final starPaint = Paint()
      ..color = AppTheme.gridLineAccent.withValues(alpha: starPointOpacity)
      ..style = PaintingStyle.fill;

    // Star points at 6, 24, 42 positions (corners and center regions)
    for (int x in [6, 24, 42]) {
      for (int y in [6, 24, 42]) {
        if (x < board.size && y < board.size) {
          final px = x * cellSize + cellSize / 2;
          final py = y * cellSize + cellSize / 2;
          canvas.drawCircle(Offset(px, py), cellSize * 0.1, starPaint);
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

  void _drawGhostStones(Canvas canvas) {
    if (capturedPositions.isEmpty || capturedColor == null) return;

    for (final pos in capturedPositions) {
      _drawGhostStone(canvas, pos, capturedColor!);
    }
  }

  void _drawGhostStone(Canvas canvas, Position pos, StoneColor color) {
    final x = pos.x * cellSize + cellSize / 2;
    final y = pos.y * cellSize + cellSize / 2;
    final radius = cellSize * 0.42;

    // Draw ghost stone with transparency
    if (color == StoneColor.black) {
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.ghostBlackFill);
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.ghostBlackBorder);
    } else {
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.ghostWhiteFill);
      canvas.drawCircle(Offset(x, y), radius, _PaintCache.ghostWhiteBorder);
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
        oldDelegate.enclosures.length != enclosures.length ||
        oldDelegate.capturedPositions.length != capturedPositions.length ||
        oldDelegate.scale != scale;
  }
}
