import '../models/models.dart';

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
  /// Process a move: place stone, check for encirclement captures
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

    // Check for encirclement captures
    // Find all opponent stones that are now enclosed by the player's stones
    final capturedPositions = _findEnclosedStones(newBoard, color.opponent);

    // Remove captured stones
    if (capturedPositions.isNotEmpty) {
      newBoard = newBoard.removeStones(capturedPositions);
    }

    return MoveResult.valid(
      board: newBoard,
      capture: CaptureResult(
        newBoard: newBoard,
        capturedPositions: capturedPositions,
      ),
    );
  }

  /// Find all stones of the given color that are enclosed (cannot reach the board edge)
  /// A stone is enclosed if it cannot reach the board edge through empty spaces
  /// or through its own color stones
  static Set<Position> _findEnclosedStones(Board board, StoneColor targetColor) {
    final enclosed = <Position>{};
    final checkedRegions = <Position>{};

    // Check each stone of the target color
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (board.getStoneAt(pos) != targetColor) continue;
        if (checkedRegions.contains(pos)) continue;

        // Find the region containing this stone (target color stones + empty spaces)
        // and check if it can reach the board edge
        final regionResult = _findRegionAndCheckEscape(board, pos, targetColor);

        checkedRegions.addAll(regionResult.region);

        if (!regionResult.canEscape) {
          // All target color stones in this region are captured
          for (final regionPos in regionResult.region) {
            if (board.getStoneAt(regionPos) == targetColor) {
              enclosed.add(regionPos);
            }
          }
        }
      }
    }

    return enclosed;
  }

  /// Find a region starting from a target stone and check if it can escape
  /// A region includes the target color stones and any empty spaces they can reach
  /// The region can escape if any empty space in it touches the board edge
  static _RegionResult _findRegionAndCheckEscape(
    Board board,
    Position startPos,
    StoneColor targetColor,
  ) {
    final region = <Position>{};
    final toVisit = <Position>[startPos];
    bool canEscape = false;

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (region.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;

      final stone = board.getStoneAt(current);

      // We can traverse through target color stones and empty spaces
      // We cannot traverse through opponent stones (they form the encirclement)
      if (stone != null && stone != targetColor) continue;

      region.add(current);

      // Check if this position is on the board edge (escape route)
      if (_isOnEdge(current, board.size)) {
        // If an empty space is on the edge, the region can escape
        if (stone == null) {
          canEscape = true;
        }
      }

      // Add adjacent positions to visit
      for (final adjacent in current.adjacentPositions) {
        if (!region.contains(adjacent)) {
          toVisit.add(adjacent);
        }
      }
    }

    return _RegionResult(region: region, canEscape: canEscape);
  }

  /// Check if a position is on the edge of the board
  static bool _isOnEdge(Position pos, int boardSize) {
    return pos.x == 0 ||
           pos.y == 0 ||
           pos.x == boardSize - 1 ||
           pos.y == boardSize - 1;
  }

  /// Check if a move would be valid (without actually making it)
  static bool isValidMove(Board board, Position pos, StoneColor color) {
    return processMove(board, pos, color).isValid;
  }
}

class _RegionResult {
  final Set<Position> region;
  final bool canEscape;

  _RegionResult({required this.region, required this.canEscape});
}
