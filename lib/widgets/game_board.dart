import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'board_painter.dart';
import 'starfield_background.dart';

class GameBoard extends ConsumerStatefulWidget {
  final bool enabled;

  const GameBoard({
    super.key,
    this.enabled = true,
  });

  @override
  ConsumerState<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends ConsumerState<GameBoard> {
  final TransformationController _transformationController =
      TransformationController();

  static const double _cellSize = 30.0;
  static const double _minScale = 0.3;
  static const double _maxScale = 3.0;
  static const double _boardPadding = 100.0;

  Offset _parallaxOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = _transformationController.value;
    // Extract translation from transformation matrix
    final translation = Offset(matrix.entry(0, 3), matrix.entry(1, 3));
    if (translation != _parallaxOffset) {
      setState(() {
        _parallaxOffset = translation;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState == null) {
      return const Center(child: Text('No game in progress'));
    }

    final boardSize = gameState.board.size * _cellSize;
    final totalSize = boardSize + _boardPadding * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        return StarfieldBackground(
          parallaxOffset: _parallaxOffset,
          child: InteractiveViewer(
            transformationController: _transformationController,
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
                      cellSize: _cellSize,
                      enclosures: gameState.enclosures,
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
    final gridX = (adjustedX / _cellSize).floor();
    final gridY = (adjustedY / _cellSize).floor();

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
