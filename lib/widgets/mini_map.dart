import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class MiniMap extends StatelessWidget {
  final Board board;
  final double size;
  final TransformationController? transformationController;
  final double cellSize;
  final Size? viewportSize;

  const MiniMap({
    super.key,
    required this.board,
    this.size = 80,
    this.transformationController,
    this.cellSize = 30.0,
    this.viewportSize,
  });

  void _onTapDown(TapDownDetails details) {
    if (transformationController == null || viewportSize == null) return;

    final tapPosition = details.localPosition;

    // Convert mini-map tap to board coordinates
    final miniMapCellSize = size / board.size;
    final boardX = tapPosition.dx / miniMapCellSize * cellSize;
    final boardY = tapPosition.dy / miniMapCellSize * cellSize;

    // Calculate the offset to center the view on the tapped position
    // We want the tapped point to be in the center of the viewport
    final targetX = -(boardX - viewportSize!.width / 2);
    final targetY = -(boardY - viewportSize!.height / 2);

    // Get current scale from transformation matrix
    final matrix = transformationController!.value;
    final scale = matrix.getMaxScaleOnAxis();

    // Create new transformation matrix with same scale but new translation
    final newMatrix = Matrix4.identity()
      ..scale(scale, scale, 1.0)
      ..setTranslationRaw(targetX, targetY, 0);

    transformationController!.value = newMatrix;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.boardBackground,
          border: Border.all(color: AppTheme.gridLineAccent, width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: CustomPaint(
          painter: MiniMapPainter(board: board),
        ),
      ),
    );
  }
}

class MiniMapPainter extends CustomPainter {
  final Board board;

  MiniMapPainter({required this.board});

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / board.size;

    // Draw grid (simplified - just a few lines)
    final gridPaint = Paint()
      ..color = AppTheme.gridLine.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (int i = 0; i < board.size; i += 6) {
      final pos = i * cellSize;
      canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), gridPaint);
      canvas.drawLine(Offset(0, pos), Offset(size.width, pos), gridPaint);
    }

    // Draw stones
    for (final entry in board.stones.entries) {
      final x = entry.key.x * cellSize + cellSize / 2;
      final y = entry.key.y * cellSize + cellSize / 2;
      final radius = cellSize * 0.6;

      final paint = Paint()
        ..color = entry.value == StoneColor.black
            ? AppTheme.blackStone
            : AppTheme.whiteStone
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), radius.clamp(1, 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    return oldDelegate.board != board;
  }
}
