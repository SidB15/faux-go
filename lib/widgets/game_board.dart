import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'board_painter.dart';
import 'starfield_background.dart';

class GameBoard extends ConsumerStatefulWidget {
  final bool enabled;
  final TransformationController transformationController;

  const GameBoard({
    super.key,
    this.enabled = true,
    required this.transformationController,
  });

  static const double cellSize = 30.0;

  @override
  ConsumerState<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends ConsumerState<GameBoard> {
  static const double _minScale = 0.3;
  static const double _maxScale = 3.0;
  static const double _boardPadding = 100.0;

  Offset _parallaxOffset = Offset.zero;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = widget.transformationController.value;
    // Extract translation from transformation matrix
    final translation = Offset(matrix.entry(0, 3), matrix.entry(1, 3));
    // Extract scale from transformation matrix
    final scale = matrix.getMaxScaleOnAxis();

    if (translation != _parallaxOffset || scale != _currentScale) {
      setState(() {
        _parallaxOffset = translation;
        _currentScale = scale;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState == null) {
      return const Center(child: Text('No game in progress'));
    }

    final boardSize = gameState.board.size * GameBoard.cellSize;
    final totalSize = boardSize + _boardPadding * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        return StarfieldBackground(
          parallaxOffset: _parallaxOffset,
          child: InteractiveViewer(
            transformationController: widget.transformationController,
            minScale: _minScale,
            maxScale: _maxScale,
            constrained: false,
            boundaryMargin: EdgeInsets.all(constraints.maxWidth),
            child: GestureDetector(
              onTapUp: (details) => _handleTap(details, gameState),
              child: Container(
                width: totalSize,
                height: totalSize,
                color: Colors.transparent,
                child: Center(
                  child: CustomPaint(
                    size: Size(boardSize, boardSize),
                    painter: BoardPainter(
                      board: gameState.board,
                      lastMove: gameState.lastMove,
                      cellSize: GameBoard.cellSize,
                      enclosures: gameState.enclosures,
                      capturedPositions: gameState.lastCapturedPositions,
                      capturedColor: gameState.lastCapturedColor,
                      scale: _currentScale,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(TapUpDetails details, GameState gameState) {
    if (gameState.status != GameStatus.playing) return;
    if (!widget.enabled) return;

    final localPosition = details.localPosition;

    // Adjust for padding offset
    final adjustedX = localPosition.dx - _boardPadding;
    final adjustedY = localPosition.dy - _boardPadding;

    // Convert tap position to grid position
    final gridX = (adjustedX / GameBoard.cellSize).floor();
    final gridY = (adjustedY / GameBoard.cellSize).floor();

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
