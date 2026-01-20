import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'capture_logic.dart';
import 'liberty_calculator.dart';

/// Data class for passing AI calculation parameters to isolate
class _AiCalculationParams {
  final Board board;
  final StoneColor aiColor;
  final AiLevel level;
  final Position? opponentLastMove;
  final List<Enclosure> enclosures;

  _AiCalculationParams(this.board, this.aiColor, this.level, this.opponentLastMove, this.enclosures);
}

/// Top-level function for compute() - must be static/top-level
Position? _calculateMoveIsolate(_AiCalculationParams params) {
  final engine = AiEngine._internal();
  return engine._calculateMoveSync(params.board, params.aiColor, params.level, params.opponentLastMove, params.enclosures);
}

/// AI Engine for Go game with 10 difficulty levels
class AiEngine {
  final Random _random = Random();

  AiEngine();

  /// Internal constructor for isolate use
  AiEngine._internal();

  /// Calculate the best move for the AI based on difficulty level (async, runs in isolate)
  /// [opponentLastMove] is used to focus AI moves near the opponent's last play
  /// [enclosures] prevents AI from placing inside opponent's forts
  Future<Position?> calculateMoveAsync(Board board, StoneColor aiColor, AiLevel level, {Position? opponentLastMove, List<Enclosure> enclosures = const []}) async {
    return compute(_calculateMoveIsolate, _AiCalculationParams(board, aiColor, level, opponentLastMove, enclosures));
  }

  /// Synchronous version for internal use
  Position? calculateMove(Board board, StoneColor aiColor, AiLevel level, {Position? opponentLastMove, List<Enclosure> enclosures = const []}) {
    return _calculateMoveSync(board, aiColor, level, opponentLastMove, enclosures);
  }

  /// Internal synchronous calculation
  Position? _calculateMoveSync(Board board, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures) {
    // Build per-turn cache to avoid redundant flood-fills
    final cache = _buildTurnCache(board, aiColor, enclosures);

    // CRITICAL: Find positions where opponent could capture our stones
    // These must be included in candidates and given highest priority
    final criticalBlockingPositions = _findCriticalBlockingPositions(board, aiColor, enclosures, cache);

    // Find chokepoints that reduce opponent's escape robustness
    final chokepoints = _findChokepoints(board, cache, aiColor);

    final candidateMoves = _getValidMoves(board, aiColor, enclosures, opponentLastMove, cache, criticalBlockingPositions, chokepoints);

    if (candidateMoves.isEmpty) {
      return null; // AI should pass
    }

    // STEP 1: Apply HARD VETO rules before scoring
    // This prevents AI from placing stones that are dead on placement
    final validMoves = <Position>[];
    for (final pos in candidateMoves) {
      if (!_isVetoedMove(board, pos, aiColor, enclosures)) {
        validMoves.add(pos);
      }
    }

    if (validMoves.isEmpty) {
      return null; // All moves vetoed - AI should pass
    }

    // STEP 2: Score remaining valid moves
    final scoredMoves = <_ScoredMove>[];
    for (final pos in validMoves) {
      final score = _evaluateMove(board, pos, aiColor, level, opponentLastMove, enclosures, cache, criticalBlockingPositions);
      scoredMoves.add(_ScoredMove(pos, score));
    }

    // Sort by score (highest first)
    scoredMoves.sort((a, b) => b.score.compareTo(a.score));

    // STEP 3: Based on AI level, choose move with some randomness
    // Lower levels make more random moves, higher levels pick better moves
    return _selectMoveByLevel(scoredMoves, level);
  }

  /// HARD VETO RULE: Check if a move should be rejected outright
  /// A move is vetoed if:
  /// 0. Dead-on-placement - no edge reach after placement (strongest veto)
  /// 1. The stone would be trapped (no escape path to edge)
  /// 2. The stone is in a "danger zone" - area about to be enclosed
  /// 3. The opponent can complete encirclement with 1 move
  /// UNLESS it satisfies an exception condition
  bool _isVetoedMove(Board board, Position pos, StoneColor aiColor, List<Enclosure> enclosures) {
    // Simulate placing the stone
    final newBoard = board.placeStone(pos, aiColor);

    // Check if the placed stone can reach the board edge through empty spaces
    final escapeResult = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // VETO 0: Dead-on-placement - no edge reach after placement
    // This is the strongest veto - catches "placing inside sealed pocket" instantly
    if (escapeResult.edgeExitCount == 0) {
      // Check for dead-placement exceptions
      if (_hasDeadPlacementException(board, newBoard, pos, aiColor, enclosures)) {
        return false; // Exception applies - allow the move
      }
      return true; // VETO - placing in sealed pocket with no edge reach
    }

    // VETO 1: Already trapped (no escape)
    if (!escapeResult.canEscape) {
      // Stone is trapped - check for exceptions
      if (_hasVetoException(board, newBoard, pos, aiColor, enclosures, escapeResult)) {
        return false; // Exception applies - allow the move
      }
      return true; // VETO - completely trapped
    }

    // VETO 2: Danger zone - area is about to be enclosed
    // If escape path is very narrow (few edge exits AND mostly surrounded by opponent)
    if (_isInDangerZone(board, pos, aiColor, escapeResult)) {
      // Check if this move itself blocks the encirclement
      if (_isBlockingEncirclement(board, pos, aiColor)) {
        return false; // Allow - this move fights back
      }
      return true; // VETO - walking into a trap
    }

    // VETO 3: Check if opponent can complete encirclement with exactly 1 move
    // This catches cases where the region looks safe but is 1 move from being sealed
    if (_isOneMoveFromEncirclement(board, pos, aiColor, escapeResult)) {
      // Only allow if we're actively blocking their wall
      if (_isBlockingEncirclement(board, pos, aiColor)) {
        return false;
      }
      return true; // VETO - opponent can seal us in with one stone
    }

    return false; // Not vetoed
  }

  /// Check if a dead-on-placement move qualifies for an exception
  /// Exceptions:
  /// 1. Move causes immediate capture
  /// 2. Move connects to an existing friendly region that has edge reach
  /// 3. Move increases edge exits of that region (escape creation)
  bool _hasDeadPlacementException(
    Board originalBoard,
    Board newBoard,
    Position pos,
    StoneColor aiColor,
    List<Enclosure> enclosures,
  ) {
    // Exception 1: Move immediately captures opponent stones
    final captureResult = CaptureLogic.processMove(originalBoard, pos, aiColor, existingEnclosures: enclosures);
    if (captureResult.isValid && captureResult.captureResult != null) {
      if (captureResult.captureResult!.captureCount > 0) {
        // This move captures - check if after capture we have escape
        final boardAfterCapture = captureResult.newBoard!;
        final escapeAfterCapture = _checkEscapePathDetailed(boardAfterCapture, pos, aiColor);
        if (escapeAfterCapture.edgeExitCount > 0) {
          return true; // Capturing creates edge reach
        }
      }
    }

    // Exception 2: Connects to a friendly group that already has edge reach
    for (final adjacent in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adjacent)) continue;
      if (newBoard.getStoneAt(adjacent) == aiColor) {
        // Found friendly stone - check if that group has edge reach
        final friendlyEdgeReach = _countEdgeExitsForGroup(newBoard, {adjacent});
        if (friendlyEdgeReach > 0) {
          return true; // Connected to a group with edge reach
        }
      }
    }

    // Exception 3: Move increases edge exits of a connected region
    // (Already implicitly covered by exception 2 - if connecting to a group with edge reach,
    // the combined region will have edge reach)

    return false;
  }

  /// Check if opponent can complete an encirclement around this position with exactly 1 move
  /// OPTIMIZED: Early returns and limited simulations for performance
  bool _isOneMoveFromEncirclement(Board board, Position pos, StoneColor aiColor, _EscapeResult escapeResult) {
    final opponentColor = aiColor.opponent;

    // Early return: safe if many exits (3+ is generally safe)
    if (escapeResult.edgeExitCount >= 3) {
      return false;
    }

    // Early return: large regions are safe
    if (escapeResult.emptyRegion.length > 25) {
      return false;
    }

    // Find critical gaps - positions where opponent could seal us in
    // Only look at positions that would actually reduce edge exits
    final criticalGaps = <Position>[];

    for (final emptyPos in escapeResult.emptyRegion) {
      // Only check positions near edge exits (the chokepoints)
      if (!_isOnEdge(emptyPos, board.size) && escapeResult.edgeExitCount > 1) {
        continue; // Skip interior positions if we have multiple exits
      }

      for (final adj in emptyPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == opponentColor) {
          // This empty position is next to an opponent stone
          // Check if placing an opponent stone at any nearby empty would complete encirclement
          for (final nearEmpty in emptyPos.adjacentPositions) {
            if (!board.isValidPosition(nearEmpty)) continue;
            if (board.isEmpty(nearEmpty) && !escapeResult.emptyRegion.contains(nearEmpty)) {
              // This empty position is outside our region but adjacent to it
              if (!criticalGaps.contains(nearEmpty)) {
                criticalGaps.add(nearEmpty);
              }
            }
          }
        }
      }
    }

    // Limit to 2 simulations max for performance
    final gapsToTest = criticalGaps.take(2);

    // For each critical gap, simulate opponent placing there and check if we'd be trapped
    for (final gap in gapsToTest) {
      // Simulate opponent placing at this gap
      final simulatedBoard = board.placeStone(gap, opponentColor);
      // Now simulate us placing at our intended position
      final afterOurMove = simulatedBoard.placeStone(pos, aiColor);
      // Check if we can still escape
      final escapeAfter = _checkEscapePathDetailed(afterOurMove, pos, aiColor);

      if (!escapeAfter.canEscape) {
        // Opponent can trap us with one stone - this is dangerous!
        return true;
      }
    }

    return false;
  }

  /// Check if a position is in a "danger zone" - an area about to be enclosed
  /// Criteria: Limited escape routes AND high opponent presence on perimeter
  /// CRITICAL: Also checks if opponent can close the encirclement in 1-2 moves
  /// ENHANCED: More aggressive detection of forming encirclements
  bool _isInDangerZone(Board board, Position pos, StoneColor aiColor, _EscapeResult escapeResult) {
    final opponentColor = aiColor.opponent;

    // CRITICAL CHECK: Can opponent complete encirclement in 1-2 moves?
    // Find the "critical gaps" - empty positions on edge exits that opponent could fill
    if (escapeResult.edgeExitCount <= 4 && escapeResult.emptyRegion.length < 40) {
      final criticalGaps = _findCriticalGaps(board, escapeResult.emptyRegion, opponentColor);

      // If opponent can close ALL remaining exits with 1-2 moves, this is extremely dangerous
      if (criticalGaps.isNotEmpty && criticalGaps.length >= escapeResult.edgeExitCount) {
        // Opponent can seal this area completely - VETO
        return true;
      }

      // Even if there are a few exits, if most can be closed quickly, it's dangerous
      if (escapeResult.edgeExitCount <= 3 && criticalGaps.isNotEmpty) {
        return true;
      }
    }

    // ENHANCED: Count opponent stones on the perimeter of this region
    // Use a more aggressive threshold for detecting danger
    int opponentPerimeterCount = 0;
    int totalPerimeterCount = 0;
    int aiPerimeterCount = 0;

    for (final emptyPos in escapeResult.emptyRegion) {
      for (final adj in emptyPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        final stone = board.getStoneAt(adj);
        if (stone != null) {
          totalPerimeterCount++;
          if (stone == opponentColor) {
            opponentPerimeterCount++;
          } else {
            aiPerimeterCount++;
          }
        }
      }
    }

    // If opponent controls most of the perimeter, it's a danger zone
    if (totalPerimeterCount > 0) {
      final opponentRatio = opponentPerimeterCount / totalPerimeterCount;

      // ENHANCED THRESHOLDS:
      // Few exits (1-2) with any significant opponent presence = danger
      if (escapeResult.edgeExitCount <= 2) {
        if (opponentRatio > 0.35) return true;  // Lowered from 0.4/0.6
      }

      // Medium exits (3-4) with high opponent presence = danger
      if (escapeResult.edgeExitCount <= 4 && escapeResult.emptyRegion.length < 25) {
        if (opponentRatio > 0.5) return true;  // New check
      }

      // Small region with opponent dominance = danger regardless of exits
      if (escapeResult.emptyRegion.length < 15 && opponentRatio > 0.6) {
        return true;
      }

      // If opponent has way more stones than us on perimeter, we're losing the battle
      if (opponentPerimeterCount > aiPerimeterCount * 2 && escapeResult.edgeExitCount <= 4) {
        return true;
      }
    }

    return false;
  }

  /// Find "critical gaps" - empty positions that are adjacent to edge exits
  /// and could be filled by opponent to seal the escape routes
  List<Position> _findCriticalGaps(Board board, Set<Position> emptyRegion, StoneColor opponentColor) {
    final criticalGaps = <Position>[];

    for (final emptyPos in emptyRegion) {
      // Check if this empty position is on the edge
      if (_isOnEdge(emptyPos, board.size)) {
        // Find adjacent empty positions that are NOT on the edge
        // These are the "chokepoints" that could seal this exit
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (board.isEmpty(adj) && !_isOnEdge(adj, board.size)) {
            // This is an interior position adjacent to an edge exit
            // Check if opponent has stones nearby (could place here to seal)
            bool opponentNearby = false;
            for (final adjAdj in adj.adjacentPositions) {
              if (!board.isValidPosition(adjAdj)) continue;
              if (board.getStoneAt(adjAdj) == opponentColor) {
                opponentNearby = true;
                break;
              }
            }
            if (opponentNearby && !criticalGaps.contains(adj)) {
              criticalGaps.add(adj);
            }
          }
        }

        // Also check: is this edge position itself a chokepoint?
        // If opponent has stones on both sides along the edge, placing here seals it
        int opponentAdjacentOnEdge = 0;
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (board.getStoneAt(adj) == opponentColor && _isOnEdge(adj, board.size)) {
            opponentAdjacentOnEdge++;
          }
        }
        // If opponent stones flank this edge position, it's a critical gap
        if (opponentAdjacentOnEdge >= 1 && !criticalGaps.contains(emptyPos)) {
          criticalGaps.add(emptyPos);
        }
      }
    }

    return criticalGaps;
  }

  /// Check if placing a stone at this position would block an opponent's encirclement
  bool _isBlockingEncirclement(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;

    // Count adjacent opponent stones - if surrounded by opponent, we're blocking their wall
    int adjacentOpponent = 0;

    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      final stone = board.getStoneAt(adj);
      if (stone == opponentColor) {
        adjacentOpponent++;
      }
    }

    // If we're placing between opponent stones, we're disrupting their wall
    if (adjacentOpponent >= 2) {
      return true;
    }

    // Check if this position is a "gap" in opponent's forming wall
    // Look for opponent stones in a line/curve pattern around this position
    return _isGapInOpponentWall(board, pos, opponentColor);
  }

  /// Check if position is a gap in opponent's wall formation
  bool _isGapInOpponentWall(Board board, Position pos, StoneColor opponentColor) {
    // Check 8 directions for opponent stone patterns
    final directions = [
      [Position(-1, 0), Position(1, 0)],   // horizontal
      [Position(0, -1), Position(0, 1)],   // vertical
      [Position(-1, -1), Position(1, 1)], // diagonal
      [Position(-1, 1), Position(1, -1)], // anti-diagonal
    ];

    for (final pair in directions) {
      bool hasOpponentOnBothSides = true;
      for (final dir in pair) {
        bool foundOpponent = false;
        // Look up to 2 cells in each direction
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;
          final stone = board.getStoneAt(checkPos);
          if (stone == opponentColor) {
            foundOpponent = true;
            break;
          } else if (stone != null) {
            // Our stone - breaks the opponent's line
            break;
          }
        }
        if (!foundOpponent) {
          hasOpponentOnBothSides = false;
          break;
        }
      }
      if (hasOpponentOnBothSides) {
        return true; // This position is a gap in opponent's wall
      }
    }

    return false;
  }

  /// Flood-fill from the placed stone through empty spaces to check for edge escape
  /// Returns detailed escape result with edge exit count for danger zone detection
  _EscapeResult _checkEscapePathDetailed(Board board, Position startPos, StoneColor aiColor) {
    final visited = <Position>{};
    final toVisit = <Position>[startPos];
    final emptyRegion = <Position>{};
    final edgeExits = <Position>{}; // Track unique edge exit positions
    bool canEscape = false;

    // Start by adding the stone position
    visited.add(startPos);

    // Check adjacent empty positions from the stone
    for (final adjacent in startPos.adjacentPositions) {
      if (board.isValidPosition(adjacent) && board.isEmpty(adjacent)) {
        toVisit.add(adjacent);
      }
    }

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;

      // We only traverse through empty spaces
      if (!board.isEmpty(current)) continue;

      visited.add(current);
      emptyRegion.add(current);

      // Check if this empty position is on the board edge
      if (_isOnEdge(current, board.size)) {
        canEscape = true;
        edgeExits.add(current);
      }

      // Add adjacent empty positions
      for (final adjacent in current.adjacentPositions) {
        if (!visited.contains(adjacent) && board.isValidPosition(adjacent)) {
          if (board.isEmpty(adjacent)) {
            toVisit.add(adjacent);
          }
        }
      }
    }

    return _EscapeResult(
      canEscape: canEscape,
      emptyRegion: emptyRegion,
      edgeExitCount: edgeExits.length,
    );
  }

  /// Check if the move qualifies for a veto exception
  bool _hasVetoException(
    Board originalBoard,
    Board newBoard,
    Position pos,
    StoneColor aiColor,
    List<Enclosure> enclosures,
    _EscapeResult escapeResult,
  ) {
    // Exception 1: Move immediately captures opponent stones (counter-encirclement)
    final captureResult = CaptureLogic.processMove(originalBoard, pos, aiColor, existingEnclosures: enclosures);
    if (captureResult.isValid && captureResult.captureResult != null) {
      if (captureResult.captureResult!.captureCount > 0) {
        // This move captures - check if after capture we have escape
        final boardAfterCapture = captureResult.newBoard!;
        final escapeAfterCapture = _checkEscapePathDetailed(boardAfterCapture, pos, aiColor);
        if (escapeAfterCapture.canEscape) {
          return true; // Capturing creates escape path
        }
      }
    }

    // Exception 2: Connects to a friendly group that already has an edge path
    for (final adjacent in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adjacent)) continue;
      if (newBoard.getStoneAt(adjacent) == aiColor) {
        // Found friendly stone - check if that group has escape
        final friendlyEscape = _checkGroupEscapePath(newBoard, adjacent, aiColor);
        if (friendlyEscape) {
          return true; // Connected to a group with escape
        }
      }
    }

    // Exception 3: The move itself creates a new escape path after placement
    // (This is already covered by the main escape check, but we double-check
    // in case the stone placement changes the topology)
    if (escapeResult.canEscape) {
      return true;
    }

    return false;
  }

  /// Check if a group (starting from any stone in it) has an escape path to the edge
  bool _checkGroupEscapePath(Board board, Position groupStone, StoneColor color) {
    // Find all stones in this group
    final group = <Position>{};
    final toVisit = <Position>[groupStone];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (group.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (board.getStoneAt(current) != color) continue;

      group.add(current);

      for (final adjacent in current.adjacentPositions) {
        if (!group.contains(adjacent)) {
          toVisit.add(adjacent);
        }
      }
    }

    // Now check if any empty space adjacent to this group can reach the edge
    final checkedEmpty = <Position>{};
    for (final stone in group) {
      for (final adjacent in stone.adjacentPositions) {
        if (!board.isValidPosition(adjacent)) continue;
        if (!board.isEmpty(adjacent)) continue;
        if (checkedEmpty.contains(adjacent)) continue;

        // Flood-fill from this empty space
        final escapeCheck = _floodFillToEdge(board, adjacent);
        if (escapeCheck) {
          return true;
        }
        // Mark all visited positions to avoid re-checking
        checkedEmpty.add(adjacent);
      }
    }

    return false;
  }

  /// Simple flood-fill to check if an empty position can reach the board edge
  bool _floodFillToEdge(Board board, Position start) {
    final visited = <Position>{};
    final toVisit = <Position>[start];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (!board.isEmpty(current)) continue;

      visited.add(current);

      if (_isOnEdge(current, board.size)) {
        return true;
      }

      for (final adjacent in current.adjacentPositions) {
        if (!visited.contains(adjacent)) {
          toVisit.add(adjacent);
        }
      }
    }

    return false;
  }

  /// Check if a position is on the board edge
  bool _isOnEdge(Position pos, int boardSize) {
    return pos.x == 0 || pos.y == 0 || pos.x == boardSize - 1 || pos.y == boardSize - 1;
  }

  /// Get valid move positions - optimized with deduplication grid and cache-aware filtering
  /// Generates candidates from:
  /// 1. CRITICAL: Positions where opponent could capture our stones (must block!)
  /// 2. Chokepoints that reduce opponent's escape robustness
  /// 3. All empty cells within radius 2 of any stone
  /// 4. Boundary gaps of endangered AI regions (edgeExits <= 3)
  /// 5. Boundary gaps of low-exit opponent regions (attack targets, edgeExits <= 4)
  List<Position> _getValidMoves(Board board, StoneColor color, List<Enclosure> enclosures, Position? opponentLastMove, _TurnCache cache, Set<Position> criticalBlockingPositions, Set<Position> chokepoints) {
    final validMoves = <Position>[];
    // Deduplication grid to avoid adding same position multiple times
    final considered = List.generate(board.size, (_) => List.filled(board.size, false));

    // Helper to add candidate if not already considered
    // Also rejects moves inside ANY enclosure (both players)
    void addCandidate(Position pos) {
      if (!board.isValidPosition(pos)) return;
      if (considered[pos.x][pos.y]) return;
      considered[pos.x][pos.y] = true;

      // BLOCK: Don't allow moves inside any enclosure (useless moves)
      for (final enclosure in enclosures) {
        if (enclosure.containsPosition(pos)) {
          return; // Skip - inside an enclosure
        }
      }

      if (board.isEmpty(pos) && _isValidMoveQuick(board, pos, color, enclosures)) {
        validMoves.add(pos);
      }
    }

    // Helper to add candidates in radius
    void addCandidatesInRadius(Position center, int radius) {
      for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
          addCandidate(Position(center.x + dx, center.y + dy));
        }
      }
    }

    // 0. CRITICAL: Always include positions where opponent could capture our stones
    // These must be considered regardless of other filters
    for (final criticalPos in criticalBlockingPositions) {
      addCandidate(criticalPos);
    }

    // 1. Chokepoints that reduce opponent's escape robustness (high-value targets)
    for (final chokepoint in chokepoints) {
      addCandidate(chokepoint);
    }

    // If board is empty or nearly empty, start near opponent's move
    if (board.stones.length < 4) {
      if (opponentLastMove != null) {
        // Start near opponent's first move (within 3 cells)
        addCandidatesInRadius(opponentLastMove, 3);
      } else {
        // No opponent move yet - fallback to center
        final center = board.size ~/ 2;
        addCandidatesInRadius(Position(center, center), 3);
      }
      return validMoves;
    }

    // 2. All empty cells within radius 2 of any stone
    for (final stonePos in board.stones.keys) {
      addCandidatesInRadius(stonePos, 2);
    }

    // 3. Boundary gaps of endangered AI regions (edgeExits <= 3)
    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 3) {
        for (final gap in group.boundaryEmpties) {
          addCandidate(gap);
        }
      }
    }

    // 4. Boundary gaps of low-exit opponent regions (attack targets, edgeExits <= 4)
    for (final group in cache.opponentGroups) {
      if (group.edgeExitCount <= 4) {
        for (final gap in group.boundaryEmpties) {
          addCandidate(gap);
        }
      }
    }

    return validMoves;
  }

  /// Quick move validation - checks if position is empty and not inside opponent's enclosure
  /// Full capture simulation happens only during scoring
  bool _isValidMoveQuick(Board board, Position pos, StoneColor color, List<Enclosure> enclosures) {
    // Basic validation: position must be empty and on board
    if (!board.isValidPosition(pos) || !board.isEmpty(pos)) {
      return false;
    }
    // Check if position is inside opponent's enclosure (fort)
    for (final enclosure in enclosures) {
      if (enclosure.owner != color && enclosure.containsPosition(pos)) {
        return false;
      }
    }
    // For now, accept all empty positions in candidate set
    // The full processMove in _evaluateMove will catch any invalid moves
    return true;
  }

  /// Evaluate a move and return a score
  /// OPTIMIZED: Difficulty-based feature gating to reduce computation at lower levels
  double _evaluateMove(
      Board board, Position pos, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures, _TurnCache cache, Set<Position> criticalBlockingPositions) {
    double score = 0.0;
    final levelValue = level.level; // 1-10

    // Simulate placing the stone
    final result = CaptureLogic.processMove(board, pos, aiColor, existingEnclosures: enclosures);
    if (!result.isValid) return -1000; // Invalid move

    final newBoard = result.newBoard!;
    final capturedCount = result.captureResult?.captureCount ?? 0;
    final newEnclosures = result.captureResult?.newEnclosures ?? [];

    // === ALWAYS COMPUTED (all levels) ===

    // 0. CRITICAL DEFENSE: If this position blocks opponent capture, MASSIVE bonus
    // This is computed at ALL levels because survival is paramount
    if (criticalBlockingPositions.contains(pos)) {
      score += 1000; // Highest priority - must block capture threats
    }

    // 1. Capture bonus (high priority) - always important
    score += capturedCount * 80;

    // 1.5 HIGHEST PRIORITY: Complete encirclement when possible!
    if (newEnclosures.isNotEmpty) {
      score += 200;
      for (final enclosure in newEnclosures) {
        score += enclosure.interiorPositions.length * 5;
      }
    }

    // 2. Proximity to opponent's last move (keeps game focused) - always important
    score += _evaluateProximityToOpponent(board, pos, opponentLastMove);

    // 9. Connection bonus (connect own groups) - simple, always useful
    score += _evaluateConnection(board, pos, aiColor) * 5;

    // 7. Center bonus - simple calculation, always useful
    score += _evaluateCenterBonus(board, pos) * 1;

    // === LEVEL 3+: Add urgent defense and capture blocking ===
    if (levelValue >= 3) {
      // 11.5 URGENT: Check if we MUST block to survive
      score += _evaluateUrgentDefense(board, pos, aiColor) * 50;

      // 11.6 CRITICAL: Check if opponent could capture our stones (detailed check)
      score += _evaluateCaptureBlockingMove(board, pos, aiColor, enclosures, criticalBlockingPositions) * 1;

      // Local empties (renamed from liberties) - minor tiebreaker
      score += _evaluateLocalEmpties(newBoard, pos, aiColor) * 1;

      // 5. Contest opponent stones nearby
      score += _evaluateContestOpponent(board, pos, aiColor) * 8;
    }

    // === LEVEL 3+: Penalty for placing in contested/surrounded positions ===
    if (levelValue >= 3) {
      // CRITICAL: Penalize moves where we're being surrounded
      score -= _evaluateSurroundedPenalty(board, pos, aiColor) * 25;
    }

    // === LEVEL 6+: Add encirclement progress and blocking ===
    if (levelValue >= 6) {
      // 11. Bonus for blocking opponent's encirclement attempts
      score += _evaluateEncirclementBlock(board, pos, aiColor) * 30;

      // 12. Bonus for progressing our own encirclement (uses cache)
      score += _evaluateEncirclementProgress(board, pos, aiColor, cache) * 15;

      // 13. NEW: Escape robustness reduction - reward moves that create chokepoints
      score += _evaluateEscapeRobustnessReduction(board, pos, aiColor, cache) * 20;

      // 6. Expand territory
      score += _evaluateExpansion(board, pos, aiColor) * 3;

      // 8. Avoid self-atari
      score -= _evaluateSelfAtari(newBoard, pos, aiColor) * 20;
    }

    // === LEVEL 9+: Full evaluation with expansion path analysis ===
    if (levelValue >= 9) {
      // 10. Penalize cramped positions
      score -= _evaluateExpansionPathPenalty(newBoard, pos, aiColor) * 10;
    }

    // === TACTICAL IMPACT GATING ===
    // Penalize moves with zero tactical impact (not near any group, not blocking, not capturing)
    if (capturedCount == 0 && newEnclosures.isEmpty && !criticalBlockingPositions.contains(pos)) {
      // Check if this move has any strategic value
      bool hasImpact = false;

      // Near our endangered groups?
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 3 && _isGroupNearPosition(group, pos, 2)) {
          hasImpact = true;
          break;
        }
      }

      // Near opponent groups we could attack?
      if (!hasImpact) {
        for (final group in cache.opponentGroups) {
          if (group.edgeExitCount <= 4 && _isGroupNearPosition(group, pos, 2)) {
            hasImpact = true;
            break;
          }
        }
      }

      // If no tactical impact, apply penalty
      if (!hasImpact) {
        score -= 30;
      }
    }

    return score;
  }

  /// Evaluate if this move progresses toward completing an encirclement of opponent stones
  /// Rewards moves that reduce opponent's escape routes
  /// OPTIMIZED: Uses cache and only considers groups near the candidate move
  double _evaluateEncirclementProgress(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    final opponentColor = aiColor.opponent;
    double progressScore = 0;

    // Only consider opponent groups within distance 4 of the move
    // or groups whose boundary empties include pos or adjacent to pos
    for (final group in cache.opponentGroups) {
      if (!_isGroupNearPosition(group, pos, 4)) continue;

      // Skip groups that are already very safe (many exits)
      if (group.edgeExitCount > 6) continue;

      // Use cached edge exit count as "before" value
      final exitsBefore = group.edgeExitCount;

      // Simulate our move
      final newBoard = board.placeStone(pos, aiColor);

      // Pick a representative stone from the group
      final oppStone = group.stones.first;

      // Check escape after our move
      final escapeAfter = _checkEscapePathDetailed(newBoard, oppStone, opponentColor);

      // Reward reducing edge exits (tightening the encirclement)
      if (escapeAfter.edgeExitCount < exitsBefore) {
        progressScore += (exitsBefore - escapeAfter.edgeExitCount) * 3;

        // Extra bonus if we're getting close to completing (few exits left)
        if (escapeAfter.edgeExitCount <= 2) {
          progressScore += 5;
        }
        if (escapeAfter.edgeExitCount == 1) {
          progressScore += 10; // Very close to completing!
        }
      }
    }

    return progressScore;
  }

  /// Check if a group is within a certain distance of a position
  bool _isGroupNearPosition(_GroupInfo group, Position pos, int maxDistance) {
    // Check if any stone in the group is within distance
    for (final stone in group.stones) {
      final dx = (stone.x - pos.x).abs();
      final dy = (stone.y - pos.y).abs();
      if (dx <= maxDistance && dy <= maxDistance) {
        return true;
      }
    }
    // Also check if pos is in boundary empties
    if (group.boundaryEmpties.contains(pos)) {
      return true;
    }
    // Check if pos is adjacent to boundary empties
    for (final adj in pos.adjacentPositions) {
      if (group.boundaryEmpties.contains(adj)) {
        return true;
      }
    }
    return false;
  }

  /// Evaluate if this move blocks an opponent's encirclement attempt on our stones
  /// CRITICAL: High priority for saving our stones from being surrounded
  double _evaluateEncirclementBlock(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double blockScore = 0;

    // CRITICAL CHECK: Are any of our stones about to be encircled?
    // Find our stones that are in danger and check if this move helps them
    final endangeredStones = _findEndangeredStones(board, aiColor);

    if (endangeredStones.isNotEmpty) {
      // Check if this move helps any endangered stones escape
      final newBoard = board.placeStone(pos, aiColor);

      for (final endangeredPos in endangeredStones) {
        // Check escape before and after our move
        final escapeBefore = _checkEscapePathDetailed(board, endangeredPos, aiColor);
        final escapeAfter = _checkEscapePathDetailed(newBoard, endangeredPos, aiColor);

        // Huge bonus if this move increases escape routes for endangered stones
        if (escapeAfter.edgeExitCount > escapeBefore.edgeExitCount) {
          blockScore += 15; // Big bonus for opening escape route
        }

        // Bonus if we're connecting to an endangered group
        for (final adj in pos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (board.getStoneAt(adj) == aiColor) {
            // We're connecting to a friendly stone - check if it's endangered
            if (endangeredStones.contains(adj)) {
              blockScore += 10; // Bonus for reinforcing endangered group
            }
          }
        }
      }
    }

    // Check if we're filling a gap in opponent's wall (disrupting their encirclement)
    if (_isGapInOpponentWall(board, pos, opponentColor)) {
      blockScore += 8; // Strong bonus for blocking a wall gap
    }

    // Count how many opponent stones are adjacent
    int adjacentOpponent = 0;
    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (board.getStoneAt(adj) == opponentColor) {
        adjacentOpponent++;
      }
    }

    // Bonus for disrupting opponent formations
    if (adjacentOpponent >= 2) {
      blockScore += adjacentOpponent * 2; // Bonus for each adjacent opponent stone
    }

    // Check if this move opens up a trapped region
    // Simulate placing and see if we create escape routes for our stones
    final newBoard = board.placeStone(pos, aiColor);
    final escapeAfter = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // If this move creates multiple escape routes, it's valuable
    if (escapeAfter.edgeExitCount >= 3) {
      blockScore += 3;
    }

    return blockScore;
  }

  /// Find AI stones that are in danger of being encircled (few escape routes)
  Set<Position> _findEndangeredStones(Board board, StoneColor aiColor) {
    final endangered = <Position>{};
    final checked = <Position>{};

    // Check all AI stones
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (board.getStoneAt(pos) != aiColor) continue;
        if (checked.contains(pos)) continue;

        // Check escape path for this stone
        final escapeResult = _checkEscapePathDetailed(board, pos, aiColor);

        // Mark all stones in this region as checked
        checked.add(pos);

        // If escape routes are limited, these stones are endangered
        if (escapeResult.edgeExitCount <= 3) {
          endangered.add(pos);

          // Also add all connected AI stones to endangered list
          for (final adj in pos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (board.getStoneAt(adj) == aiColor) {
              endangered.add(adj);
            }
          }
        }
      }
    }

    return endangered;
  }

  /// Evaluate URGENT defensive moves - when opponent is about to complete encirclement
  /// Returns very high score for moves that are the ONLY way to prevent capture
  double _evaluateUrgentDefense(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double urgentScore = 0;

    // Find all AI stones and check if any group has very limited escape
    final aiStones = <Position>[];
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final p = Position(x, y);
        if (board.getStoneAt(p) == aiColor) {
          aiStones.add(p);
        }
      }
    }

    if (aiStones.isEmpty) return 0;

    // Check each AI stone group for danger
    final checkedGroups = <Position>{};
    for (final stone in aiStones) {
      if (checkedGroups.contains(stone)) continue;

      final escapeResult = _checkEscapePathDetailed(board, stone, aiColor);
      checkedGroups.addAll(escapeResult.emptyRegion);
      checkedGroups.add(stone);

      // If this group has very few escape exits (1-2), check if our move helps
      if (escapeResult.edgeExitCount <= 2 && escapeResult.emptyRegion.length < 15) {
        // This group is in CRITICAL danger!
        // Check if placing at pos would help

        // Option 1: pos is adjacent to an escape route and blocks opponent from sealing it
        for (final emptyPos in escapeResult.emptyRegion) {
          if (_isOnEdge(emptyPos, board.size)) {
            // This is an edge escape - check if pos is adjacent to it
            final dist = (pos.x - emptyPos.x).abs() + (pos.y - emptyPos.y).abs();
            if (dist <= 2) {
              // Check if pos would block opponent from sealing this escape
              bool adjacentToOpponent = false;
              for (final adj in pos.adjacentPositions) {
                if (board.getStoneAt(adj) == opponentColor) {
                  adjacentToOpponent = true;
                  break;
                }
              }
              if (adjacentToOpponent) {
                urgentScore += 8; // Critical defensive move
              }
            }
          }
        }

        // Option 2: This move directly improves the endangered group's escape
        final newBoard = board.placeStone(pos, aiColor);
        final escapeAfter = _checkEscapePathDetailed(newBoard, stone, aiColor);

        if (escapeAfter.edgeExitCount > escapeResult.edgeExitCount) {
          urgentScore += 10; // This move opens more escapes - vital!
        }

        // If we'd be completely trapped without this move but saved with it
        if (!escapeResult.canEscape || escapeResult.edgeExitCount == 1) {
          if (escapeAfter.canEscape && escapeAfter.edgeExitCount >= 2) {
            urgentScore += 15; // Life-saving move!
          }
        }
      }
    }

    return urgentScore;
  }

  /// CRITICAL: Check if this position blocks opponent from capturing our stones
  /// Simulates: "If opponent placed here instead, would they capture our stones?"
  /// If yes, this is a MUST-BLOCK position
  double _evaluateCaptureBlockingMove(Board board, Position pos, StoneColor aiColor, List<Enclosure> enclosures, Set<Position> criticalBlockingPositions) {
    final opponentColor = aiColor.opponent;
    double blockingScore = 0;

    // HIGHEST PRIORITY: If this position is in the pre-computed critical blocking set
    // These are positions where opponent could capture our stones
    if (criticalBlockingPositions.contains(pos)) {
      blockingScore += 500; // Massive bonus - must block!
    }

    // Simulate opponent placing at this position
    final opponentMoveResult = CaptureLogic.processMove(board, pos, opponentColor, existingEnclosures: enclosures);

    if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
      final wouldCapture = opponentMoveResult.captureResult!.captureCount;

      if (wouldCapture > 0) {
        // CRITICAL: Opponent could capture our stones here!
        // We MUST block this position
        blockingScore += 50 + (wouldCapture * 20); // Increased from 10 + 5*stones
      }

      // Also check if opponent would create a new enclosure (fort) that traps us
      final wouldCreateEnclosure = opponentMoveResult.captureResult!.newEnclosures.isNotEmpty;
      if (wouldCreateEnclosure) {
        blockingScore += 30; // Increased from 8
      }
    }

    // Also check adjacent positions - would opponent placing nearby capture us?
    // This is for "almost complete" encirclements
    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (!board.isEmpty(adj)) continue;

      final adjMoveResult = CaptureLogic.processMove(board, adj, opponentColor, existingEnclosures: enclosures);
      if (adjMoveResult.isValid && adjMoveResult.captureResult != null) {
        final wouldCapture = adjMoveResult.captureResult!.captureCount;
        if (wouldCapture > 0) {
          // Opponent could capture nearby - check if our move at pos prevents this
          final boardWithOurMove = board.placeStone(pos, aiColor);
          final afterOurMove = CaptureLogic.processMove(boardWithOurMove, adj, opponentColor, existingEnclosures: enclosures);

          if (!afterOurMove.isValid ||
              afterOurMove.captureResult == null ||
              afterOurMove.captureResult!.captureCount < wouldCapture) {
            // Our move prevents or reduces the capture!
            blockingScore += 20 + (wouldCapture * 10); // Increased from 5 + 2*stones
          }
        }
      }
    }

    return blockingScore;
  }

  /// Find all positions where opponent could capture our stones on their next move
  /// These are CRITICAL positions that must be blocked
  /// ENHANCED: Also detects forming encirclements earlier (edgeExits <= 4)
  Set<Position> _findCriticalBlockingPositions(Board board, StoneColor aiColor, List<Enclosure> enclosures, _TurnCache cache) {
    final criticalPositions = <Position>{};
    final opponentColor = aiColor.opponent;

    // Check all boundary empties of AI groups - these are potential capture points
    for (final group in cache.aiGroups) {
      // Check each boundary empty to see if opponent placing there would capture
      for (final emptyPos in group.boundaryEmpties) {
        final opponentMoveResult = CaptureLogic.processMove(board, emptyPos, opponentColor, existingEnclosures: enclosures);

        if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
          if (opponentMoveResult.captureResult!.captureCount > 0) {
            // Opponent could capture here - this is critical!
            criticalPositions.add(emptyPos);
          }
          if (opponentMoveResult.captureResult!.newEnclosures.isNotEmpty) {
            // Opponent could create an enclosure - also critical!
            criticalPositions.add(emptyPos);
          }
        }
      }

      // ENHANCED: Detect forming encirclements EARLIER (edgeExits <= 4, was <= 2)
      // Also look at positions that significantly reduce our escape options
      if (group.edgeExitCount <= 4) {
        // Find positions that could complete or progress the encirclement
        for (final stone in group.stones) {
          for (final adj in stone.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (!board.isEmpty(adj)) continue;

            // Check if opponent placing here would reduce our escape
            final simulatedBoard = board.placeStone(adj, opponentColor);
            final escapeAfter = _checkEscapePathDetailed(simulatedBoard, stone, aiColor);

            // CRITICAL: Block if it would completely seal us
            if (!escapeAfter.canEscape || escapeAfter.edgeExitCount == 0) {
              criticalPositions.add(adj);
            }
            // IMPORTANT: Also block moves that significantly reduce our escape
            else if (escapeAfter.edgeExitCount < group.edgeExitCount - 1) {
              // Losing 2+ exits is serious - add to critical
              criticalPositions.add(adj);
            }
          }
        }

        // ADDITIONAL: Find gaps in opponent's wall around our group
        // These are empty positions between opponent stones that form a wall
        final wallGaps = _findWallGapsAroundGroup(board, group, opponentColor);
        criticalPositions.addAll(wallGaps);
      }
    }

    return criticalPositions;
  }

  /// Find gaps in opponent's wall formation around an AI group
  /// These are empty positions that, if filled by us, would break the encirclement
  Set<Position> _findWallGapsAroundGroup(Board board, _GroupInfo group, StoneColor opponentColor) {
    final gaps = <Position>{};

    // Look at all positions within distance 2 of any stone in the group
    for (final stone in group.stones) {
      for (int dx = -2; dx <= 2; dx++) {
        for (int dy = -2; dy <= 2; dy++) {
          if (dx == 0 && dy == 0) continue;
          final checkPos = Position(stone.x + dx, stone.y + dy);
          if (!board.isValidPosition(checkPos)) continue;
          if (!board.isEmpty(checkPos)) continue;

          // Count opponent stones adjacent to this empty position
          int adjacentOpponent = 0;
          bool adjacentToOurGroup = false;

          for (final adj in checkPos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            final adjStone = board.getStoneAt(adj);
            if (adjStone == opponentColor) {
              adjacentOpponent++;
            }
            if (group.stones.contains(adj)) {
              adjacentToOurGroup = true;
            }
          }

          // This is a wall gap if:
          // 1. It's adjacent to 2+ opponent stones (they're forming a wall)
          // 2. It's near our group (either adjacent or within 1 cell)
          if (adjacentOpponent >= 2) {
            // Check if it's near our group
            if (adjacentToOurGroup || group.boundaryEmpties.contains(checkPos)) {
              gaps.add(checkPos);
            } else {
              // Check if it's 1 cell away from our boundary
              for (final adj in checkPos.adjacentPositions) {
                if (group.boundaryEmpties.contains(adj)) {
                  gaps.add(checkPos);
                  break;
                }
              }
            }
          }
        }
      }
    }

    return gaps;
  }

  /// Penalize moves placed in regions with fewer than 2 empty expansion paths
  /// This makes AI avoid cramped positions that are strategically weak
  double _evaluateExpansionPathPenalty(Board board, Position pos, StoneColor aiColor) {
    // Count distinct expansion directions (empty paths leading away)
    int expansionDirections = 0;

    // Check each orthogonal direction for open paths
    final directions = [
      Position(1, 0),   // right
      Position(-1, 0),  // left
      Position(0, 1),   // down
      Position(0, -1),  // up
    ];

    for (final dir in directions) {
      // Look up to 3 cells in each direction for open space
      bool hasOpenPath = false;
      for (int dist = 1; dist <= 3; dist++) {
        final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
        if (!board.isValidPosition(checkPos)) break;

        final stone = board.getStoneAt(checkPos);
        if (stone == null) {
          // Empty space - this direction has potential
          hasOpenPath = true;
          break;
        } else if (stone != aiColor) {
          // Opponent stone blocks this direction
          break;
        }
        // Own stone - continue checking
      }
      if (hasOpenPath) expansionDirections++;
    }

    // Penalize positions with fewer than 2 expansion paths
    if (expansionDirections < 2) {
      return 3.0 - expansionDirections; // 3 penalty for 0 paths, 2 for 1 path
    }

    return 0;
  }

  /// Evaluate proximity to opponent's last move - AI MUST respond nearby
  /// This is the most important factor for keeping the game focused
  double _evaluateProximityToOpponent(Board board, Position pos, Position? opponentLastMove) {
    if (opponentLastMove == null) return 0;

    // Calculate Chebyshev distance (max of dx, dy) - this is "grid distance"
    final dx = (pos.x - opponentLastMove.x).abs();
    final dy = (pos.y - opponentLastMove.y).abs();
    final distance = max(dx, dy); // Chebyshev distance (1-2 grid cells)

    // VERY strong bonus for moves within 1-2 cells of opponent's last move
    // and PENALTY for moves further away
    if (distance <= 1) {
      return 50; // Adjacent - highest priority
    } else if (distance <= 2) {
      return 35; // 2 cells away - very good
    } else if (distance <= 3) {
      return 10; // 3 cells - acceptable
    } else if (distance <= 4) {
      return -10; // Starting to get far - slight penalty
    } else {
      return -30; // Too far - strong penalty to discourage
    }
  }

  /// Evaluate moves that contest opponent's territory/stones
  double _evaluateContestOpponent(Board board, Position pos, StoneColor aiColor) {
    double contestScore = 0;
    final opponentColor = aiColor.opponent;

    // Check for opponent stones within a radius of 2 (tight focus)
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nearPos = Position(pos.x + dx, pos.y + dy);
        if (!board.isValidPosition(nearPos)) continue;

        if (board.getStoneAt(nearPos) == opponentColor) {
          final distance = max(dx.abs(), dy.abs()); // Chebyshev distance
          // Bonus for being near opponent stones (to contest them)
          if (distance == 1) {
            contestScore += 5; // Adjacent - direct contest
          } else if (distance == 2) {
            contestScore += 2; // 2 cells away
          }
        }
      }
    }

    return contestScore;
  }

  /// Evaluate local empty adjacencies (minor tiebreaker)
  /// In Faux Go, adjacent empties are weak compared to edge-reachability
  /// This is kept as a minor signal, not a major scoring factor
  double _evaluateLocalEmpties(Board board, Position pos, StoneColor aiColor) {
    double score = 0;
    final opponentColor = aiColor.opponent;
    final calculator = LibertyCalculator(board);

    // Check adjacent opponent groups - minor bonus for reducing their local empties
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != opponentColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Minor bonus for reducing opponent's local empties (tiebreaker only)
      if (liberties.length == 1) {
        score += group.length * 1.0; // Reduced from 5
      } else if (liberties.length == 2) {
        score += group.length * 0.5; // Reduced from 2
      }
    }

    // Check if this move helps our own groups' local empties
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != aiColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Minor bonus for adding local empties to our groups
      if (liberties.length == 1) {
        score += group.length * 2.0; // Reduced from 10
      } else if (liberties.length == 2) {
        score += group.length * 0.5; // Reduced from 3
      }
    }

    return score;
  }

  /// Evaluate expansion value
  double _evaluateExpansion(Board board, Position pos, StoneColor aiColor) {
    double expansionScore = 0;

    // Prefer moves near own stones (within 2 cells)
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nearPos = Position(pos.x + dx, pos.y + dy);
        if (!board.isValidPosition(nearPos)) continue;

        if (board.getStoneAt(nearPos) == aiColor) {
          final distance = max(dx.abs(), dy.abs()); // Chebyshev distance
          if (distance == 2) {
            expansionScore += 3; // Good expansion distance
          } else if (distance == 1) {
            expansionScore += 1; // Adjacent - connected
          }
        }
      }
    }

    return expansionScore;
  }

  /// CRITICAL: Penalize moves in positions where we're being surrounded
  /// Checks if opponent has stones on multiple sides forming an encirclement
  double _evaluateSurroundedPenalty(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double penalty = 0;

    // Count opponent stones in each direction (8 directions)
    // If opponent has presence on 3+ sides, we're being surrounded
    int sidesWithOpponent = 0;
    int totalOpponentNearby = 0;

    // Check 8 directions in groups of 2 (opposite sides)
    final directionPairs = [
      [Position(-1, 0), Position(1, 0)],   // left/right
      [Position(0, -1), Position(0, 1)],   // up/down
      [Position(-1, -1), Position(1, 1)], // diagonals
      [Position(-1, 1), Position(1, -1)], // diagonals
    ];

    for (final pair in directionPairs) {
      for (final dir in pair) {
        // Look up to 2 cells in each direction
        bool foundOpponent = false;
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;

          final stone = board.getStoneAt(checkPos);
          if (stone == opponentColor) {
            foundOpponent = true;
            totalOpponentNearby++;
            break;
          } else if (stone == aiColor) {
            // Our stone - friendly, stop looking
            break;
          }
        }
        if (foundOpponent) sidesWithOpponent++;
      }
    }

    // Strong penalty if opponent has stones on 3+ sides (forming encirclement)
    if (sidesWithOpponent >= 4) {
      penalty += 8; // Heavily surrounded
    } else if (sidesWithOpponent >= 3) {
      penalty += 4; // Mostly surrounded
    }

    // Additional penalty based on total opponent presence nearby
    if (totalOpponentNearby >= 5) {
      penalty += 3;
    } else if (totalOpponentNearby >= 4) {
      penalty += 2;
    }

    // Check for "pincer" patterns - opponent on opposite sides
    for (final pair in directionPairs) {
      bool hasOpponentOnBothEnds = true;
      for (final dir in pair) {
        bool found = false;
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;
          if (board.getStoneAt(checkPos) == opponentColor) {
            found = true;
            break;
          } else if (board.getStoneAt(checkPos) != null) {
            break;
          }
        }
        if (!found) {
          hasOpponentOnBothEnds = false;
          break;
        }
      }
      if (hasOpponentOnBothEnds) {
        penalty += 3; // We're in a pincer (opponent on opposite sides)
      }
    }

    return penalty;
  }

  /// Evaluate center bonus (prefer center over edges)
  double _evaluateCenterBonus(Board board, Position pos) {
    final center = board.size / 2;
    final distFromCenter =
        ((pos.x - center).abs() + (pos.y - center).abs()) / board.size;

    // Higher score for moves closer to center
    return (1 - distFromCenter) * 5;
  }

  /// Evaluate self-atari risk
  double _evaluateSelfAtari(Board board, Position pos, StoneColor aiColor) {
    final calculator = LibertyCalculator(board);
    final group = calculator.findGroup(pos);
    final liberties = calculator.getGroupLiberties(group);

    if (liberties.length == 1) {
      return group.length * 5; // Bad - putting ourselves in atari
    } else if (liberties.length == 2) {
      return group.length * 1; // Slightly risky
    }

    return 0;
  }

  /// Evaluate connection value
  double _evaluateConnection(Board board, Position pos, StoneColor aiColor) {
    double connectionScore = 0;
    int ownAdjacent = 0;

    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) == aiColor) {
        ownAdjacent++;
      }
    }

    // Bonus for connecting groups (but not too many adjacent - that's inefficient)
    if (ownAdjacent == 1 || ownAdjacent == 2) {
      connectionScore = 3;
    }

    return connectionScore;
  }

  /// Calculate minimum cut to edge using articulation point heuristic
  /// Returns estimated min-cut (1, 2, or 3+ meaning safe)
  /// Uses a local window around the target region for performance
  ///
  /// This measures "robustness" - how many independent paths exist to the edge
  /// A min-cut of 1 means there's a single chokepoint that can be blocked
  int _minCutToEdgeLocal(Board board, Set<Position> targetStones, int windowRadius) {
    if (targetStones.isEmpty) return 3;

    // Find the bounding box of target stones
    int minX = board.size, maxX = 0, minY = board.size, maxY = 0;
    for (final stone in targetStones) {
      if (stone.x < minX) minX = stone.x;
      if (stone.x > maxX) maxX = stone.x;
      if (stone.y < minY) minY = stone.y;
      if (stone.y > maxY) maxY = stone.y;
    }

    // Expand window by radius
    final windowMinX = (minX - windowRadius).clamp(0, board.size - 1);
    final windowMaxX = (maxX + windowRadius).clamp(0, board.size - 1);
    final windowMinY = (minY - windowRadius).clamp(0, board.size - 1);
    final windowMaxY = (maxY + windowRadius).clamp(0, board.size - 1);

    // Build local empty graph within window
    final emptyInWindow = <Position>{};
    for (int x = windowMinX; x <= windowMaxX; x++) {
      for (int y = windowMinY; y <= windowMaxY; y++) {
        final pos = Position(x, y);
        if (board.isEmpty(pos)) {
          emptyInWindow.add(pos);
        }
      }
    }

    if (emptyInWindow.isEmpty) return 0; // Completely surrounded

    // Find empty positions adjacent to target stones (starting points)
    final startPoints = <Position>{};
    for (final stone in targetStones) {
      for (final adj in stone.adjacentPositions) {
        if (emptyInWindow.contains(adj)) {
          startPoints.add(adj);
        }
      }
    }

    if (startPoints.isEmpty) return 0; // No adjacent empties

    // Find edge positions in window (end points)
    final edgePositions = <Position>{};
    for (final pos in emptyInWindow) {
      if (_isOnEdge(pos, board.size)) {
        edgePositions.add(pos);
      }
    }

    // If window touches edge and has direct path, check articulation points
    if (edgePositions.isEmpty) {
      // Window doesn't reach edge - need to check if paths exist outside window
      // For now, estimate based on openings at window boundary
      int boundaryOpenings = 0;
      for (final pos in emptyInWindow) {
        if (pos.x == windowMinX || pos.x == windowMaxX ||
            pos.y == windowMinY || pos.y == windowMaxY) {
          // Check if adjacent position outside window is empty
          for (final adj in pos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (adj.x < windowMinX || adj.x > windowMaxX ||
                adj.y < windowMinY || adj.y > windowMaxY) {
              if (board.isEmpty(adj)) {
                boundaryOpenings++;
              }
            }
          }
        }
      }
      return boundaryOpenings.clamp(0, 3);
    }

    // Use articulation point heuristic to estimate min-cut
    // Count independent paths from startPoints to edgePositions
    return _countIndependentPaths(board, startPoints, edgePositions, emptyInWindow);
  }

  /// Count independent paths using iterative path removal
  /// Returns min(pathCount, 3) for efficiency
  int _countIndependentPaths(Board board, Set<Position> starts, Set<Position> ends, Set<Position> validPositions) {
    if (starts.isEmpty || ends.isEmpty) return 0;

    // Check if any start is directly an edge
    for (final start in starts) {
      if (ends.contains(start)) return 3; // Direct edge access = very safe
    }

    int pathCount = 0;
    final blocked = <Position>{};

    // Find up to 3 independent paths
    for (int i = 0; i < 3; i++) {
      final path = _findPathBFS(starts, ends, validPositions, blocked);
      if (path == null) break;

      pathCount++;

      // Block the narrowest point of this path (articulation point approximation)
      // Find the position in path with fewest unblocked neighbors
      Position? chokePoint;
      int minNeighbors = 5;

      for (final pos in path) {
        if (starts.contains(pos) || ends.contains(pos)) continue;

        int neighborCount = 0;
        for (final adj in pos.adjacentPositions) {
          if (validPositions.contains(adj) && !blocked.contains(adj)) {
            neighborCount++;
          }
        }

        if (neighborCount < minNeighbors) {
          minNeighbors = neighborCount;
          chokePoint = pos;
        }
      }

      if (chokePoint != null) {
        blocked.add(chokePoint);
      } else if (path.isNotEmpty) {
        // Block middle of path if no clear chokepoint
        blocked.add(path.elementAt(path.length ~/ 2));
      }
    }

    return pathCount;
  }

  /// BFS to find a path from any start to any end, avoiding blocked positions
  Set<Position>? _findPathBFS(Set<Position> starts, Set<Position> ends, Set<Position> valid, Set<Position> blocked) {
    final visited = <Position>{};
    final parent = <Position, Position?>{};
    final queue = <Position>[];

    for (final start in starts) {
      if (!blocked.contains(start) && valid.contains(start)) {
        queue.add(start);
        visited.add(start);
        parent[start] = null;
      }
    }

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      if (ends.contains(current)) {
        // Reconstruct path
        final path = <Position>{};
        Position? node = current;
        while (node != null) {
          path.add(node);
          node = parent[node];
        }
        return path;
      }

      for (final adj in current.adjacentPositions) {
        if (!visited.contains(adj) && valid.contains(adj) && !blocked.contains(adj)) {
          visited.add(adj);
          parent[adj] = current;
          queue.add(adj);
        }
      }
    }

    return null; // No path found
  }

  /// Evaluate escape robustness reduction - how much does this move reduce opponent's escape paths
  /// High weight for moves that reduce min-cut from 2+ to 1 (creating chokepoint)
  double _evaluateEscapeRobustnessReduction(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    double score = 0;

    // Only evaluate groups that are already somewhat constrained
    for (final group in cache.opponentGroups) {
      if (!_isGroupNearPosition(group, pos, 3)) continue;
      if (group.edgeExitCount > 8) continue; // Already very safe, skip

      // Calculate min-cut before our move
      final minCutBefore = _minCutToEdgeLocal(board, group.stones, 6);

      // Skip if already very robust
      if (minCutBefore >= 3) continue;

      // Simulate our move
      final newBoard = board.placeStone(pos, aiColor);

      // Calculate min-cut after our move
      final minCutAfter = _minCutToEdgeLocal(newBoard, group.stones, 6);

      // Reward reducing robustness
      if (minCutAfter < minCutBefore) {
        final reduction = minCutBefore - minCutAfter;
        score += reduction * 15;

        // Extra bonus for creating single chokepoint
        if (minCutAfter == 1) {
          score += 25;
        }

        // Massive bonus for completely blocking
        if (minCutAfter == 0) {
          score += 50;
        }
      }
    }

    return score;
  }

  /// Find chokepoint positions for opponent groups (for targeted candidate generation)
  Set<Position> _findChokepoints(Board board, _TurnCache cache, StoneColor aiColor) {
    final chokepoints = <Position>{};

    for (final group in cache.opponentGroups) {
      // Only target groups that can potentially be captured
      if (group.edgeExitCount > 6) continue;

      final minCut = _minCutToEdgeLocal(board, group.stones, 6);
      if (minCut >= 3) continue; // Too robust to target

      // Find positions that would reduce min-cut
      for (final emptyPos in group.boundaryEmpties) {
        final newBoard = board.placeStone(emptyPos, aiColor);
        final newMinCut = _minCutToEdgeLocal(newBoard, group.stones, 6);

        if (newMinCut < minCut) {
          chokepoints.add(emptyPos);
        }
      }

      // Also check positions near the escape corridors
      // These are empty positions that are on the path to edge
      for (final stone in group.stones) {
        for (int dx = -3; dx <= 3; dx++) {
          for (int dy = -3; dy <= 3; dy++) {
            final checkPos = Position(stone.x + dx, stone.y + dy);
            if (!board.isValidPosition(checkPos)) continue;
            if (!board.isEmpty(checkPos)) continue;

            // Check if this position is in a corridor (has limited neighbors)
            int emptyNeighbors = 0;
            for (final adj in checkPos.adjacentPositions) {
              if (board.isValidPosition(adj) && board.isEmpty(adj)) {
                emptyNeighbors++;
              }
            }

            // Narrow corridor = potential chokepoint
            if (emptyNeighbors <= 2) {
              final newBoard = board.placeStone(checkPos, aiColor);
              final newMinCut = _minCutToEdgeLocal(newBoard, group.stones, 6);
              if (newMinCut < minCut) {
                chokepoints.add(checkPos);
              }
            }
          }
        }
      }
    }

    return chokepoints;
  }

  /// Select a move based on AI level
  Position _selectMoveByLevel(List<_ScoredMove> scoredMoves, AiLevel level) {
    if (scoredMoves.isEmpty) {
      throw StateError('No valid moves available');
    }

    // Determine how many top moves to consider based on level
    // Higher levels consider fewer moves (more focused on best)
    // Lower levels consider more moves (more random)
    final considerCount = max(1, (scoredMoves.length * (1.1 - level.strength)).round());
    final topMoves = scoredMoves.take(considerCount).toList();

    // Add randomness based on level
    // Level 1: Very random, Level 10: Almost always best move
    if (_random.nextDouble() > level.strength) {
      // Random selection from top moves
      return topMoves[_random.nextInt(topMoves.length)].position;
    } else {
      // Pick best move (with small chance of second best for variety)
      if (topMoves.length > 1 && _random.nextDouble() < 0.1) {
        return topMoves[1].position;
      }
      return topMoves[0].position;
    }
  }

  /// Build per-turn cache of group information to avoid redundant flood-fills
  _TurnCache _buildTurnCache(Board board, StoneColor aiColor, List<Enclosure> enclosures) {
    final aiGroups = <_GroupInfo>[];
    final opponentGroups = <_GroupInfo>[];
    final forbiddenPositions = <Position>{};
    final checkedAi = <Position>{};
    final checkedOpponent = <Position>{};
    final opponentColor = aiColor.opponent;

    // Build forbidden positions from enclosures
    for (final enclosure in enclosures) {
      if (enclosure.owner != aiColor) {
        forbiddenPositions.addAll(enclosure.interiorPositions);
      }
    }

    // Find all AI groups
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        final stone = board.getStoneAt(pos);

        if (stone == aiColor && !checkedAi.contains(pos)) {
          final groupInfo = _buildGroupInfo(board, pos, aiColor, opponentColor);
          aiGroups.add(groupInfo);
          checkedAi.addAll(groupInfo.stones);
        } else if (stone == opponentColor && !checkedOpponent.contains(pos)) {
          final groupInfo = _buildGroupInfo(board, pos, opponentColor, aiColor);
          opponentGroups.add(groupInfo);
          checkedOpponent.addAll(groupInfo.stones);
        }
      }
    }

    return _TurnCache(
      aiGroups: aiGroups,
      opponentGroups: opponentGroups,
      forbiddenPositions: forbiddenPositions,
    );
  }

  /// Build information about a single connected group
  _GroupInfo _buildGroupInfo(Board board, Position startPos, StoneColor groupColor, StoneColor opponentColor) {
    final stones = <Position>{};
    final boundaryEmpties = <Position>{};
    final toVisit = <Position>[startPos];
    int opponentPerimeterCount = 0;
    int totalPerimeterCount = 0;

    // Find all stones in this group
    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (stones.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (board.getStoneAt(current) != groupColor) continue;

      stones.add(current);

      for (final adj in current.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        final adjStone = board.getStoneAt(adj);
        if (adjStone == groupColor && !stones.contains(adj)) {
          toVisit.add(adj);
        } else if (adjStone == null) {
          boundaryEmpties.add(adj);
        } else if (adjStone == opponentColor) {
          opponentPerimeterCount++;
        }
        if (adjStone != null) {
          totalPerimeterCount++;
        }
      }
    }

    // Calculate edge exit count for this group
    final edgeExitCount = _countEdgeExitsForGroup(board, stones);

    final opponentPerimeterRatio = totalPerimeterCount > 0
        ? opponentPerimeterCount / totalPerimeterCount
        : 0.0;

    return _GroupInfo(
      stones: stones,
      boundaryEmpties: boundaryEmpties,
      edgeExitCount: edgeExitCount,
      opponentPerimeterRatio: opponentPerimeterRatio,
    );
  }

  /// Count edge exits reachable from a group through empty spaces
  int _countEdgeExitsForGroup(Board board, Set<Position> groupStones) {
    final visited = <Position>{};
    final edgeExits = <Position>{};
    final toVisit = <Position>[];

    // Start from all boundary empties of the group
    for (final stone in groupStones) {
      for (final adj in stone.adjacentPositions) {
        if (board.isValidPosition(adj) && board.isEmpty(adj)) {
          toVisit.add(adj);
        }
      }
    }

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (!board.isEmpty(current)) continue;

      visited.add(current);

      if (_isOnEdge(current, board.size)) {
        edgeExits.add(current);
      }

      for (final adj in current.adjacentPositions) {
        if (!visited.contains(adj) && board.isValidPosition(adj) && board.isEmpty(adj)) {
          toVisit.add(adj);
        }
      }
    }

    return edgeExits.length;
  }
}

class _ScoredMove {
  final Position position;
  final double score;

  _ScoredMove(this.position, this.score);
}

/// Result of escape path check
class _EscapeResult {
  final bool canEscape;
  final Set<Position> emptyRegion;
  final int edgeExitCount; // Number of unique edge positions reachable

  _EscapeResult({
    required this.canEscape,
    required this.emptyRegion,
    required this.edgeExitCount,
  });
}

/// Information about a stone group for caching
class _GroupInfo {
  final Set<Position> stones;
  final Set<Position> boundaryEmpties;
  final int edgeExitCount;
  final double opponentPerimeterRatio;

  _GroupInfo({
    required this.stones,
    required this.boundaryEmpties,
    required this.edgeExitCount,
    required this.opponentPerimeterRatio,
  });
}

/// Per-turn cache to avoid redundant flood-fills
class _TurnCache {
  final List<_GroupInfo> aiGroups;
  final List<_GroupInfo> opponentGroups;
  final Set<Position> forbiddenPositions; // Inside opponent forts

  _TurnCache({
    required this.aiGroups,
    required this.opponentGroups,
    required this.forbiddenPositions,
  });
}
