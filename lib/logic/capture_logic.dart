import '../models/models.dart';
import 'liberty_calculator.dart';

class CaptureResult {
  final Board newBoard;
  final Set<Position> capturedPositions;
  final int captureCount;

  CaptureResult({
    required this.newBoard,
    required this.capturedPositions,
  }) : captureCount = capturedPositions.length;

  bool get hasCaptured => capturedPositions.isNotEmpty;
}

class MoveResult {
  final bool isValid;
  final String? errorMessage;
  final Board? newBoard;
  final CaptureResult? captureResult;

  MoveResult.valid({
    required Board board,
    CaptureResult? capture,
  })  : isValid = true,
        errorMessage = null,
        newBoard = board,
        captureResult = capture;

  MoveResult.invalid(this.errorMessage)
      : isValid = false,
        newBoard = null,
        captureResult = null;
}

class CaptureLogic {
  /// Process a move: place stone, check for captures, validate move
  static MoveResult processMove(Board board, Position pos, StoneColor color) {
    // Check if position is valid
    if (!board.isValidPosition(pos)) {
      return MoveResult.invalid('Position is outside the board');
    }

    // Check if position is empty
    if (!board.isEmpty(pos)) {
      return MoveResult.invalid('Position is already occupied');
    }

    // Place the stone
    Board newBoard = board.placeStone(pos, color);

    // Check for captures of opponent stones
    // We need to check ALL opponent groups that touch the placed position
    final capturedPositions = <Position>{};
    final opponentColor = color.opponent;
    final checkedPositions = <Position>{};

    // Check all adjacent positions for opponent stones
    for (final adjacent in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adjacent)) continue;

      final adjacentStone = newBoard.getStoneAt(adjacent);
      if (adjacentStone != opponentColor) continue;
      if (checkedPositions.contains(adjacent)) continue;

      // Find the entire group this stone belongs to
      final calculator = LibertyCalculator(newBoard);
      final group = calculator.findGroup(adjacent);

      // Mark all positions in this group as checked
      checkedPositions.addAll(group);

      // Check if this group has any liberties left
      final liberties = calculator.getGroupLiberties(group);

      if (liberties.isEmpty) {
        capturedPositions.addAll(group);
      }
    }

    // Remove captured stones
    if (capturedPositions.isNotEmpty) {
      newBoard = newBoard.removeStones(capturedPositions);
    }

    // Check for suicide (placing stone with no liberties and no captures)
    if (capturedPositions.isEmpty) {
      final calculator = LibertyCalculator(newBoard);
      final ownGroup = calculator.findGroup(pos);
      final ownLiberties = calculator.getGroupLiberties(ownGroup);

      if (ownLiberties.isEmpty) {
        return MoveResult.invalid('Suicide move is not allowed');
      }
    }

    return MoveResult.valid(
      board: newBoard,
      capture: CaptureResult(
        newBoard: newBoard,
        capturedPositions: capturedPositions,
      ),
    );
  }

  /// Check if a move would be valid (without actually making it)
  static bool isValidMove(Board board, Position pos, StoneColor color) {
    return processMove(board, pos, color).isValid;
  }
}
