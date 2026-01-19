import 'dart:math';

import '../models/models.dart';
import 'capture_logic.dart';
import 'liberty_calculator.dart';

/// AI Engine for Go game with 10 difficulty levels
class AiEngine {
  final Random _random = Random();

  /// Calculate the best move for the AI based on difficulty level
  Position? calculateMove(Board board, StoneColor aiColor, AiLevel level) {
    final validMoves = _getValidMoves(board, aiColor);

    if (validMoves.isEmpty) {
      return null; // AI should pass
    }

    // Score all valid moves
    final scoredMoves = <_ScoredMove>[];
    for (final pos in validMoves) {
      final score = _evaluateMove(board, pos, aiColor, level);
      scoredMoves.add(_ScoredMove(pos, score));
    }

    // Sort by score (highest first)
    scoredMoves.sort((a, b) => b.score.compareTo(a.score));

    // Based on AI level, choose move with some randomness
    // Lower levels make more random moves, higher levels pick better moves
    return _selectMoveByLevel(scoredMoves, level);
  }

  /// Get all valid move positions
  List<Position> _getValidMoves(Board board, StoneColor color) {
    final validMoves = <Position>[];

    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (CaptureLogic.isValidMove(board, pos, color)) {
          validMoves.add(pos);
        }
      }
    }

    return validMoves;
  }

  /// Evaluate a move and return a score
  double _evaluateMove(
      Board board, Position pos, StoneColor aiColor, AiLevel level) {
    double score = 0.0;

    // Simulate placing the stone
    final result = CaptureLogic.processMove(board, pos, aiColor);
    if (!result.isValid) return -1000; // Invalid move

    final newBoard = result.newBoard!;
    final capturedCount = result.captureResult?.captureCount ?? 0;

    // 1. Capture bonus (highest priority)
    score += capturedCount * 100;

    // 2. Threaten captures (stones with few liberties)
    score += _evaluateThreats(newBoard, pos, aiColor) * 20;

    // 3. Defend own groups (play near own stones with few liberties)
    score += _evaluateDefense(board, pos, aiColor) * 15;

    // 4. Expand territory (prefer moves near own stones)
    score += _evaluateExpansion(board, pos, aiColor) * 5;

    // 5. Avoid edges early game (center is more valuable)
    score += _evaluateCenterBonus(board, pos) * 2;

    // 6. Avoid self-atari (putting own stones in danger)
    score -= _evaluateSelfAtari(newBoard, pos, aiColor) * 30;

    // 7. Connection bonus (connect own groups)
    score += _evaluateConnection(board, pos, aiColor) * 10;

    return score;
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

    // Prefer moves near own stones (but not too close)
    for (int dx = -3; dx <= 3; dx++) {
      for (int dy = -3; dy <= 3; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nearPos = Position(pos.x + dx, pos.y + dy);
        if (!board.isValidPosition(nearPos)) continue;

        if (board.getStoneAt(nearPos) == aiColor) {
          final distance = (dx.abs() + dy.abs()).toDouble();
          if (distance >= 2 && distance <= 3) {
            expansionScore += 2; // Good expansion distance
          } else if (distance == 1) {
            expansionScore += 0.5; // Connected but not expanding much
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
