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
    final validMoves = _getValidMoves(board, aiColor, enclosures);

    if (validMoves.isEmpty) {
      return null; // AI should pass
    }

    // Score all valid moves
    final scoredMoves = <_ScoredMove>[];
    for (final pos in validMoves) {
      final score = _evaluateMove(board, pos, aiColor, level, opponentLastMove, enclosures);
      scoredMoves.add(_ScoredMove(pos, score));
    }

    // Sort by score (highest first)
    scoredMoves.sort((a, b) => b.score.compareTo(a.score));

    // Based on AI level, choose move with some randomness
    // Lower levels make more random moves, higher levels pick better moves
    return _selectMoveByLevel(scoredMoves, level);
  }

  /// Get valid move positions - optimized to focus on relevant areas
  /// Instead of checking all 2304 positions, only check near existing stones
  /// Also filters out positions inside opponent's enclosures (forts)
  List<Position> _getValidMoves(Board board, StoneColor color, List<Enclosure> enclosures) {
    final validMoves = <Position>[];
    final candidatePositions = <Position>{};

    // If board is empty or nearly empty, use strategic starting positions
    if (board.stones.length < 4) {
      // Start with center area and star points
      final center = board.size ~/ 2;
      for (int dx = -3; dx <= 3; dx++) {
        for (int dy = -3; dy <= 3; dy++) {
          candidatePositions.add(Position(center + dx, center + dy));
        }
      }
      // Add star points
      for (int x in [6, 24, 42]) {
        for (int y in [6, 24, 42]) {
          if (x < board.size && y < board.size) {
            candidatePositions.add(Position(x, y));
          }
        }
      }
    } else {
      // Focus on positions near existing stones (within radius of 2)
      // This keeps the game tight and focused
      const searchRadius = 2;
      for (final entry in board.stones.entries) {
        final stonePos = entry.key;
        for (int dx = -searchRadius; dx <= searchRadius; dx++) {
          for (int dy = -searchRadius; dy <= searchRadius; dy++) {
            final pos = Position(stonePos.x + dx, stonePos.y + dy);
            if (board.isValidPosition(pos)) {
              candidatePositions.add(pos);
            }
          }
        }
      }
    }

    // Only validate the candidate positions (much smaller set)
    // Also check that position is not inside opponent's enclosure
    for (final pos in candidatePositions) {
      if (board.isEmpty(pos) && _isValidMoveQuick(board, pos, color, enclosures)) {
        validMoves.add(pos);
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
  double _evaluateMove(
      Board board, Position pos, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures) {
    double score = 0.0;

    // Simulate placing the stone
    final result = CaptureLogic.processMove(board, pos, aiColor, existingEnclosures: enclosures);
    if (!result.isValid) return -1000; // Invalid move

    final newBoard = result.newBoard!;
    final capturedCount = result.captureResult?.captureCount ?? 0;

    // 1. Capture bonus (high priority)
    score += capturedCount * 80;

    // 2. Proximity to opponent's last move (HIGHEST PRIORITY - keeps game focused)
    // This is weighted very heavily to ensure AI stays within 1-2 cells
    score += _evaluateProximityToOpponent(board, pos, opponentLastMove);

    // 3. Threaten captures (stones with few liberties)
    score += _evaluateThreats(newBoard, pos, aiColor) * 15;

    // 4. Defend own groups (play near own stones with few liberties)
    score += _evaluateDefense(board, pos, aiColor) * 12;

    // 5. Respond to opponent stones nearby (contest their territory)
    score += _evaluateContestOpponent(board, pos, aiColor) * 8;

    // 6. Expand territory (prefer moves near own stones)
    score += _evaluateExpansion(board, pos, aiColor) * 3;

    // 7. Avoid edges early game (center is more valuable)
    score += _evaluateCenterBonus(board, pos) * 1;

    // 8. Avoid self-atari (putting own stones in danger)
    score -= _evaluateSelfAtari(newBoard, pos, aiColor) * 20;

    // 9. Connection bonus (connect own groups)
    score += _evaluateConnection(board, pos, aiColor) * 5;

    return score;
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

  /// Evaluate threats created by this move
  double _evaluateThreats(Board board, Position pos, StoneColor aiColor) {
    double threatScore = 0;
    final opponentColor = aiColor.opponent;
    final calculator = LibertyCalculator(board);

    // Check adjacent opponent groups
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != opponentColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Bonus for reducing opponent liberties
      if (liberties.length == 1) {
        threatScore += group.length * 5; // Atari - very valuable
      } else if (liberties.length == 2) {
        threatScore += group.length * 2; // Threatening
      } else if (liberties.length == 3) {
        threatScore += group.length * 0.5;
      }
    }

    return threatScore;
  }

  /// Evaluate defensive value of this move
  double _evaluateDefense(Board board, Position pos, StoneColor aiColor) {
    double defenseScore = 0;
    final calculator = LibertyCalculator(board);

    // Check if this move helps defend own groups
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != aiColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Bonus for saving groups with few liberties
      if (liberties.length == 1) {
        defenseScore += group.length * 10; // Critical defense
      } else if (liberties.length == 2) {
        defenseScore += group.length * 3;
      }
    }

    return defenseScore;
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
}

class _ScoredMove {
  final Position position;
  final double score;

  _ScoredMove(this.position, this.score);
}
