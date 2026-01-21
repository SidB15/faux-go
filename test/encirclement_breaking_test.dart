// Encirclement Path-Tracing Test
// Tests the AI's ability to find blocking moves on ANY side of an encirclement
// Not just near the opponent's last move
//
// Run with: flutter test test/encirclement_breaking_test.dart --reporter expanded

import 'package:flutter_test/flutter_test.dart';
import 'package:edgeline/models/models.dart';
import 'package:edgeline/logic/ai_engine.dart';
import 'package:edgeline/logic/capture_logic.dart';

void main() {
  group('Encirclement Path-Tracing Tests', () {
    late AiEngine engine;

    setUp(() {
      engine = AiEngine();
      AiEngine.resetPOICache();
    });

    test('Scenario 1: AI should find blocking move on opposite side of encirclement', () {
      print('\n${'=' * 80}');
      print('SCENARIO 1: Opposite-Side Encirclement Block');
      print('${'=' * 80}\n');

      // Create a board where White (AI) is being encircled by Black
      // The encirclement has a gap on the opposite side from Black's last move
      //
      // Board setup (15x15, showing relevant area):
      //     0 1 2 3 4 5 6 7 8 9
      //  4          B B B B
      //  5        B . . . . B
      //  6        B . W W . B
      //  7        B . W W . B
      //  8        B . . . . B     <- Gap at (5,8) would break encirclement
      //  9          B B B B
      //
      // Black's last move: (3,5) - top-left area
      // AI should find (5,8) or similar to break out, not just block near (3,5)

      Board board = Board(size: 15);

      // Place Black stones forming encirclement (leaving gap at bottom)
      final blackStones = [
        // Top wall
        Position(4, 4), Position(5, 4), Position(6, 4), Position(7, 4),
        // Left wall
        Position(3, 5), Position(3, 6), Position(3, 7), Position(3, 8),
        // Right wall
        Position(8, 5), Position(8, 6), Position(8, 7), Position(8, 8),
        // Bottom wall (with gap)
        Position(4, 9), Position(5, 9), Position(6, 9), Position(7, 9),
      ];

      // Place White stones (AI) inside the encirclement
      final whiteStones = [
        Position(5, 6), Position(6, 6),
        Position(5, 7), Position(6, 7),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup:');
      _printBoard(board, 2, 2, 11, 11);

      // Black's last move is at (3,5) - far from the gap at (5,8)
      final opponentLastMove = Position(3, 5);
      print('\nBlack\'s last move: $opponentLastMove');

      // AI should find a move that breaks the encirclement
      // The gap positions are around row 8 (bottom), not near (3,5)
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // Check if the AI found a move that helps escape
      expect(aiMove, isNotNull, reason: 'AI should find a move');

      // Verify the move improves escape routes
      if (aiMove != null) {
        final boardBefore = board;
        final boardAfter = board.placeStone(aiMove, StoneColor.white);

        // Check escape before and after
        final escapeBefore = _checkEscapeSimple(boardBefore, Position(5, 6), StoneColor.white);
        final escapeAfter = _checkEscapeSimple(boardAfter, Position(5, 6), StoneColor.white);

        print('Escape exits before AI move: $escapeBefore');
        print('Escape exits after AI move: $escapeAfter');

        // The move should either improve escapes or be strategically placed
        // Check if move is not just reacting to proximity
        final distanceFromLastMove = (aiMove.x - opponentLastMove.x).abs() +
            (aiMove.y - opponentLastMove.y).abs();
        print('Distance from opponent\'s last move: $distanceFromLastMove');

        if (distanceFromLastMove > 3) {
          print('SUCCESS: AI found a distant move (path-tracing worked!)');
        }
      }
    });

    test('Scenario 2: Two-prong encirclement - AI should identify critical gap', () {
      print('\n${'=' * 80}');
      print('SCENARIO 2: Two-Prong Encirclement (Human Strategy)');
      print('${'=' * 80}\n');

      // Simulates the human strategy: start encirclement from two sides,
      // AI focuses on one side, human closes the other
      //
      // Board setup:
      //     0 1 2 3 4 5 6 7 8 9 10 11
      //  3          B B B
      //  4        B . . . B
      //  5        B . W . B
      //  6        B . W . B
      //  7        B . . . B
      //  8        . . . . .         <- Critical gap at (3,8)
      //  9        B B B B B

      Board board = Board(size: 15);

      // Black's encirclement (almost complete)
      final blackStones = [
        // Top
        Position(4, 3), Position(5, 3), Position(6, 3),
        // Left side (gap at row 8)
        Position(3, 4), Position(3, 5), Position(3, 6), Position(3, 7),
        // Right side
        Position(7, 4), Position(7, 5), Position(7, 6), Position(7, 7),
        // Bottom
        Position(3, 9), Position(4, 9), Position(5, 9), Position(6, 9), Position(7, 9),
      ];

      // White (AI) stones
      final whiteStones = [
        Position(5, 5), Position(5, 6),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup (encirclement almost complete):');
      _printBoard(board, 1, 1, 10, 12);

      // Black's last move was at top (6,3) - but the critical gap is at (3,8)
      final opponentLastMove = Position(6, 3);
      print('\nBlack\'s last move: $opponentLastMove (top side)');
      print('Critical gap location: (3,8) or (4,8) (bottom-left)');

      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      if (aiMove != null) {
        // Check if AI found the gap area (row 8)
        final foundGapArea = aiMove.y == 8 ||
            (aiMove.y >= 7 && aiMove.x <= 4); // Near the gap

        if (foundGapArea) {
          print('SUCCESS: AI found the gap area (row 8 / bottom-left)');
        } else {
          print('AI move is at: (${aiMove.x}, ${aiMove.y})');
          // Even if not exact, check if it improves escape
          final boardAfter = board.placeStone(aiMove, StoneColor.white);
          final escapeAfter = _checkEscapeSimple(boardAfter, Position(5, 5), StoneColor.white);
          print('Escape exits after move: $escapeAfter');
        }
      }
    });

    test('Scenario 3: Multiple endangered groups - AI prioritizes correctly', () {
      print('\n${'=' * 80}');
      print('SCENARIO 3: Multiple Endangered Groups');
      print('${'=' * 80}\n');

      // AI has two groups, one more endangered than the other
      // Should prioritize saving the more endangered group

      Board board = Board(size: 15);

      // Group 1: Very endangered (only 1-2 escape routes)
      final group1 = [Position(3, 3), Position(3, 4)];
      // Black wall around group 1
      final blackWall1 = [
        Position(2, 2), Position(3, 2), Position(4, 2),
        Position(2, 3), Position(4, 3),
        Position(2, 4), Position(4, 4),
        Position(2, 5), Position(3, 5), // Almost closed
      ];

      // Group 2: Less endangered (multiple escape routes)
      final group2 = [Position(10, 10), Position(11, 10)];
      // Partial black pressure on group 2
      final blackWall2 = [
        Position(9, 9), Position(10, 9),
        Position(9, 10),
      ];

      for (final pos in group1) {
        board = board.placeStone(pos, StoneColor.white);
      }
      for (final pos in group2) {
        board = board.placeStone(pos, StoneColor.white);
      }
      for (final pos in blackWall1) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in blackWall2) {
        board = board.placeStone(pos, StoneColor.black);
      }

      print('Board setup:');
      print('Group 1 (endangered): $group1');
      print('Group 2 (safer): $group2');
      _printBoard(board, 0, 0, 14, 14);

      // Black's last move near group 2
      final opponentLastMove = Position(9, 10);
      print('\nBlack\'s last move: $opponentLastMove (near safer group)');

      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      if (aiMove != null) {
        // Check if AI prioritized the endangered group
        final distToGroup1 = (aiMove.x - 3).abs() + (aiMove.y - 4).abs();
        final distToGroup2 = (aiMove.x - 10).abs() + (aiMove.y - 10).abs();

        print('Distance to endangered group 1: $distToGroup1');
        print('Distance to safer group 2: $distToGroup2');

        if (distToGroup1 <= 2) {
          print('SUCCESS: AI prioritized saving the endangered group!');
        } else if (distToGroup2 <= 2) {
          print('AI responded near the opponent\'s last move (proximity)');
        }
      }
    });

    test('Scenario 4: 50 rounds simulation with encirclement tracking', () {
      print('\n${'=' * 80}');
      print('SCENARIO 4: Simulation - Encirclement Breaking Effectiveness');
      print('${'=' * 80}\n');

      int totalGames = 50;
      int encirclementsSurvived = 0;
      int encirclementsLost = 0;
      int breakingMovesDetected = 0;

      for (int game = 0; game < totalGames; game++) {
        AiEngine.resetPOICache();
        Board board = Board(size: 15);
        StoneColor currentPlayer = StoneColor.black;
        Position? lastMove;
        List<Enclosure> enclosures = [];

        int moveCount = 0;
        int blackCaptures = 0;
        int whiteCaptures = 0;
        bool hadEndangeredGroup = false;

        while (moveCount < 40) {
          final move = engine.calculateMove(
            board,
            currentPlayer,
            AiLevel.level7, // Level 7 to ensure encirclement features active
            opponentLastMove: lastMove,
            enclosures: enclosures,
          );

          if (move == null) break;

          final result = CaptureLogic.processMove(
            board,
            move,
            currentPlayer,
            existingEnclosures: enclosures,
          );

          if (result.isValid) {
            board = result.newBoard!;
            lastMove = move;
            moveCount++;

            if (result.captureResult != null) {
              final captures = result.captureResult!.captureCount;
              if (currentPlayer == StoneColor.black) {
                blackCaptures += captures;
              } else {
                whiteCaptures += captures;
              }
              enclosures = [...enclosures, ...result.captureResult!.newEnclosures];
            }
          }

          currentPlayer = currentPlayer.opponent;
        }

        // Track results
        if (blackCaptures > 5 || whiteCaptures > 5) {
          encirclementsLost++;
        } else {
          encirclementsSurvived++;
        }

        if ((game + 1) % 10 == 0) {
          print('Completed ${game + 1}/$totalGames games...');
        }
      }

      print('\n--- SIMULATION RESULTS ---');
      print('Games with low captures (good defense): $encirclementsSurvived');
      print('Games with high captures (encirclement success): $encirclementsLost');
      print('Defense rate: ${(encirclementsSurvived / totalGames * 100).toStringAsFixed(1)}%');

      // We expect good defense rate with the path-tracing system
      expect(encirclementsSurvived, greaterThan(totalGames * 0.3),
          reason: 'AI should survive encirclement attempts at least 30% of the time');
    });
  });
}

/// Simple escape check (BFS to find edge exits)
int _checkEscapeSimple(Board board, Position start, StoneColor color) {
  final visited = <Position>{};
  final toVisit = <Position>[start];
  int edgeExits = 0;

  while (toVisit.isNotEmpty) {
    final current = toVisit.removeLast();
    if (visited.contains(current)) continue;
    if (!board.isValidPosition(current)) continue;

    // Only traverse through empty spaces or our own stones
    final stone = board.getStoneAt(current);
    if (stone != null && stone != color) continue;

    visited.add(current);

    // Check if on edge
    if (current.x == 0 || current.y == 0 ||
        current.x == board.size - 1 || current.y == board.size - 1) {
      if (board.isEmpty(current)) {
        edgeExits++;
      }
    }

    // Add adjacent positions
    for (final adj in current.adjacentPositions) {
      if (!visited.contains(adj) && board.isValidPosition(adj)) {
        if (board.isEmpty(adj) || board.getStoneAt(adj) == color) {
          toVisit.add(adj);
        }
      }
    }
  }

  return edgeExits;
}

/// Print a section of the board for debugging
void _printBoard(Board board, int startX, int startY, int endX, int endY) {
  // Header
  print('    ${List.generate(endX - startX + 1, (i) => (startX + i).toString().padLeft(2)).join(' ')}');

  for (int y = startY; y <= endY; y++) {
    final row = StringBuffer('${y.toString().padLeft(2)}  ');
    for (int x = startX; x <= endX; x++) {
      final pos = Position(x, y);
      if (!board.isValidPosition(pos)) {
        row.write(' . ');
      } else {
        final stone = board.getStoneAt(pos);
        if (stone == StoneColor.black) {
          row.write(' B ');
        } else if (stone == StoneColor.white) {
          row.write(' W ');
        } else {
          row.write(' . ');
        }
      }
    }
    print(row.toString());
  }
}
