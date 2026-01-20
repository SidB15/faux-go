import '../models/models.dart';

class CaptureResult {
  final Board newBoard;
  final Set<Position> capturedPositions;
  final int captureCount;
  final List<Enclosure> newEnclosures;

  CaptureResult({
    required this.newBoard,
    required this.capturedPositions,
    this.newEnclosures = const [],
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
  /// Also checks if position is inside ANY enclosure (both players)
  /// Playing inside an enclosure has no tactical value
  static MoveResult processMove(
    Board board,
    Position pos,
    StoneColor color, {
    List<Enclosure> existingEnclosures = const [],
  }) {
    // Check if position is valid
    if (!board.isValidPosition(pos)) {
      return MoveResult.invalid('Position is outside the board');
    }

    // Check if position is empty
    if (!board.isEmpty(pos)) {
      return MoveResult.invalid('Position is already occupied');
    }

    // Check if position is inside ANY enclosure (useless move for both players)
    for (final enclosure in existingEnclosures) {
      if (enclosure.containsPosition(pos)) {
        return MoveResult.invalid('Cannot place stone inside an enclosure');
      }
    }

    // Place the stone
    Board newBoard = board.placeStone(pos, color);

    // Check for encirclement captures and get enclosure info
    final captureInfo = _findEnclosedStonesWithWalls(newBoard, color.opponent, color);

    // Remove captured stones
    if (captureInfo.capturedPositions.isNotEmpty) {
      newBoard = newBoard.removeStones(captureInfo.capturedPositions);
    }

    // Also check for empty enclosures (closed shapes without enemy stones)
    final emptyEnclosures = _findEmptyEnclosures(newBoard, color, existingEnclosures);

    // Combine capture enclosures with empty enclosures
    final allNewEnclosures = [...captureInfo.newEnclosures, ...emptyEnclosures];

    return MoveResult.valid(
      board: newBoard,
      capture: CaptureResult(
        newBoard: newBoard,
        capturedPositions: captureInfo.capturedPositions,
        newEnclosures: allNewEnclosures,
      ),
    );
  }

  /// Find all stones of the given color that are enclosed (cannot reach the board edge)
  /// A stone is enclosed if it cannot reach the board edge through empty spaces
  /// or through its own color stones
  /// Also returns the wall positions (opponent stones that form the encirclement)
  static _CaptureInfo _findEnclosedStonesWithWalls(
    Board board,
    StoneColor targetColor,
    StoneColor capturingColor,
  ) {
    final enclosed = <Position>{};
    final checkedRegions = <Position>{};
    final newEnclosures = <Enclosure>[];

    // Check each stone of the target color
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (board.getStoneAt(pos) != targetColor) continue;
        if (checkedRegions.contains(pos)) continue;

        // Find the region containing this stone (target color stones + empty spaces)
        // and check if it can reach the board edge
        final regionResult = _findRegionAndCheckEscapeWithWalls(board, pos, targetColor);

        checkedRegions.addAll(regionResult.region);

        if (!regionResult.canEscape) {
          // Collect captured positions
          final capturedInRegion = <Position>{};
          for (final regionPos in regionResult.region) {
            if (board.getStoneAt(regionPos) == targetColor) {
              enclosed.add(regionPos);
              capturedInRegion.add(regionPos);
            }
          }

          // Create enclosure with wall positions
          if (capturedInRegion.isNotEmpty && regionResult.wallPositions.isNotEmpty) {
            newEnclosures.add(Enclosure(
              owner: capturingColor,
              wallPositions: regionResult.wallPositions,
              interiorPositions: regionResult.region,
            ));
          }
        }
      }
    }

    return _CaptureInfo(
      capturedPositions: enclosed,
      newEnclosures: newEnclosures,
    );
  }

  /// Find a region starting from a target stone and check if it can escape
  /// Also tracks wall positions (opponent stones forming the encirclement)
  /// OPTIMIZED: Early termination once escape is found
  static _RegionResultWithWalls _findRegionAndCheckEscapeWithWalls(
    Board board,
    Position startPos,
    StoneColor targetColor,
  ) {
    final region = <Position>{};
    final wallPositions = <Position>{};
    final toVisit = <Position>[startPos];
    bool canEscape = false;

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (region.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;

      final stone = board.getStoneAt(current);

      // We can traverse through target color stones and empty spaces
      // We cannot traverse through opponent stones (they form the encirclement)
      if (stone != null && stone != targetColor) {
        // This is an opponent stone - it's part of the wall
        wallPositions.add(current);
        continue;
      }

      region.add(current);

      // Check if this position is on the board edge (escape route)
      if (_isOnEdge(current, board.size)) {
        // If an empty space is on the edge, the region can escape
        if (stone == null) {
          canEscape = true;
        }
      }

      // Add adjacent positions to visit
      // If we already found escape, only follow target color stones (skip empty)
      for (final adjacent in current.adjacentPositions) {
        if (!region.contains(adjacent)) {
          if (canEscape) {
            // Only continue through stones of target color to mark region
            final adjStone = board.getStoneAt(adjacent);
            if (adjStone == targetColor) {
              toVisit.add(adjacent);
            }
          } else {
            toVisit.add(adjacent);
          }
        }
      }
    }

    return _RegionResultWithWalls(
      region: region,
      canEscape: canEscape,
      wallPositions: wallPositions,
    );
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

class _RegionResultWithWalls {
  final Set<Position> region;
  final bool canEscape;
  final Set<Position> wallPositions;

  _RegionResultWithWalls({
    required this.region,
    required this.canEscape,
    required this.wallPositions,
  });
}

class _CaptureInfo {
  final Set<Position> capturedPositions;
  final List<Enclosure> newEnclosures;

  _CaptureInfo({
    required this.capturedPositions,
    required this.newEnclosures,
  });
}

/// Find empty enclosures: closed regions surrounded by a player's stones
/// with no enemy stones inside (just empty spaces or own stones)
List<Enclosure> _findEmptyEnclosures(
  Board board,
  StoneColor color,
  List<Enclosure> existingEnclosures,
) {
  final newEnclosures = <Enclosure>[];
  final checkedPositions = <Position>{};

  // Mark all positions already inside existing enclosures
  for (final enclosure in existingEnclosures) {
    checkedPositions.addAll(enclosure.interiorPositions);
  }

  // Check each empty position to see if it's enclosed by the current player
  for (int x = 0; x < board.size; x++) {
    for (int y = 0; y < board.size; y++) {
      final pos = Position(x, y);

      // Skip if already checked or not empty
      if (checkedPositions.contains(pos)) continue;
      if (!board.isEmpty(pos)) continue;

      // Flood fill to find the region of empty spaces (can include own stones)
      final regionResult = _findEmptyRegion(board, pos, color);

      // Mark all positions in this region as checked
      checkedPositions.addAll(regionResult.region);

      // If region cannot escape to edge and has walls, it's an enclosure
      if (!regionResult.canEscape &&
          regionResult.wallPositions.isNotEmpty &&
          regionResult.region.isNotEmpty) {
        // Make sure this enclosure doesn't overlap with existing ones
        final interiorOverlaps = existingEnclosures.any((e) =>
            e.interiorPositions.any((p) => regionResult.region.contains(p)));

        if (!interiorOverlaps) {
          newEnclosures.add(Enclosure(
            owner: color,
            wallPositions: regionResult.wallPositions,
            interiorPositions: regionResult.region,
          ));
        }
      }
    }
  }

  return newEnclosures;
}

/// Find a region of empty spaces (can traverse through own stones)
/// and check if it can reach the board edge
class _EmptyRegionResult {
  final Set<Position> region;
  final bool canEscape;
  final Set<Position> wallPositions;

  _EmptyRegionResult({
    required this.region,
    required this.canEscape,
    required this.wallPositions,
  });
}

_EmptyRegionResult _findEmptyRegion(
  Board board,
  Position startPos,
  StoneColor ownerColor,
) {
  final region = <Position>{};
  final wallPositions = <Position>{};
  final toVisit = <Position>[startPos];
  bool canEscape = false;

  while (toVisit.isNotEmpty) {
    final current = toVisit.removeLast();

    if (region.contains(current)) continue;
    if (!board.isValidPosition(current)) continue;

    final stone = board.getStoneAt(current);

    // If it's an opponent's stone, it's not part of this enclosure attempt
    // (we're looking for regions enclosed purely by ownerColor)
    if (stone != null && stone != ownerColor) {
      // This region touches opponent stones, not a valid empty enclosure
      canEscape = true; // Mark as "escaped" since it's not a clean enclosure
      continue;
    }

    // If it's the owner's stone, it's part of the wall
    if (stone == ownerColor) {
      wallPositions.add(current);
      continue;
    }

    // Empty space - add to region
    region.add(current);

    // Check if this position is on the board edge
    if (CaptureLogic._isOnEdge(current, board.size)) {
      canEscape = true;
    }

    // Add adjacent positions to visit
    for (final adjacent in current.adjacentPositions) {
      if (!region.contains(adjacent) && !wallPositions.contains(adjacent)) {
        toVisit.add(adjacent);
      }
    }
  }

  return _EmptyRegionResult(
    region: region,
    canEscape: canEscape,
    wallPositions: wallPositions,
  );
}
