import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class MiniMap extends StatelessWidget {
  final Board board;
  final double size;

  const MiniMap({
    super.key,
    required this.board,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.boardBackground,
        border: Border.all(color: AppTheme.gridLineAccent, width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: MiniMapPainter(board: board),
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
      ..color = AppTheme.gridLine.withOpacity(0.5)
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
