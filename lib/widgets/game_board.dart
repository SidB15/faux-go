import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'board_painter.dart';

class GameBoard extends ConsumerStatefulWidget {
  const GameBoard({super.key});

  @override
  ConsumerState<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends ConsumerState<GameBoard> {
  final TransformationController _transformationController =
      TransformationController();

  static const double _cellSize = 30.0;
  static const double _minScale = 0.3;
  static const double _maxScale = 3.0;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState == null) {
      return const Center(child: Text('No game in progress'));
    }

    final boardSize = gameState.board.size * _cellSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transformationController,
          minScale: _minScale,
          maxScale: _maxScale,
          constrained: false,
          boundaryMargin: EdgeInsets.all(constraints.maxWidth),
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details, gameState),
            child: CustomPaint(
              size: Size(boardSize, boardSize),
              painter: BoardPainter(
                board: gameState.board,
                lastMove: gameState.lastMove,
                cellSize: _cellSize,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(TapUpDetails details, GameState gameState) {
    if (gameState.status != GameStatus.playing) return;

    final localPosition = details.localPosition;

    // Convert tap position to grid position
    final gridX = (localPosition.dx / _cellSize).floor();
    final gridY = (localPosition.dy / _cellSize).floor();

    // Validate position
    if (gridX < 0 ||
        gridX >= gameState.board.size ||
        gridY < 0 ||
        gridY >= gameState.board.size) {
      return;
    }

    final position = Position(gridX, gridY);

    // Attempt to place stone
    final success = ref.read(gameStateProvider.notifier).placeStone(position);

    if (!success) {
      // Show feedback for invalid move
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid move'),
          duration: Duration(milliseconds: 500),
        ),
      );
    }
  }
}
