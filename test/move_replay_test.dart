// Move Replay Test
// Replays specific game positions to test AI decision making
//
// Run with: flutter test test/move_replay_test.dart --reporter expanded

import 'package:flutter_test/flutter_test.dart';
import 'package:edgeline/models/models.dart';
import 'package:edgeline/logic/ai_engine.dart';
import 'package:edgeline/logic/capture_logic.dart';

void main() {
  group('Move Replay Tests', () {
    late AiEngine engine;

    setUp(() {
      engine = AiEngine();
      AiEngine.resetPOICache();
    });

    test('Game 2 - Move 17: AI should detect (18,12) as capture threat', () {
      print('\n${'=' * 80}');
      print('GAME 2 - MOVE 17 ANALYSIS');
      print('${'=' * 80}\n');

      // Reconstruct board by replaying EXACT moves from the game log
      Board board = Board(size: 25);
      List<Enclosure> enclosures = [];

      // Exact moves from the game log
      final gameMoves = [
        (Position(17, 16), StoneColor.black),  // Move 1
        (Position(17, 15), StoneColor.white),  // Move 2
        (Position(18, 16), StoneColor.black),  // Move 3
        (Position(18, 15), StoneColor.white),  // Move 4
        (Position(19, 15), StoneColor.black),  // Move 5
        (Position(18, 14), StoneColor.white),  // Move 6
        (Position(19, 13), StoneColor.black),  // Move 7
        (Position(19, 14), StoneColor.white),  // Move 8
        (Position(20, 14), StoneColor.black),  // Move 9
        (Position(17, 16), StoneColor.white),  // Move 10 - wait, this conflicts!
      ];

      // The game log shows (17,16) for both Move 1 and Move 10
      // Looking at the log more carefully:
      // Move 10: white at (17, 16) [AI]
      // But Move 1: black at (17, 16) [Human]
      //
      // This is impossible unless the board is 25x25 and these are different positions
      // OR there's a capture happening. Let me replay properly.

      print('Replaying game from exact log positions...\n');

      // Actual exact moves from log (copy-pasted)
      final exactMoves = [
        ('black', 17, 16),  // Move 1
        ('white', 17, 15),  // Move 2
        ('black', 18, 16),  // Move 3
        ('white', 18, 15),  // Move 4
        ('black', 19, 15),  // Move 5
        ('white', 18, 14),  // Move 6
        ('black', 19, 13),  // Move 7
        ('white', 19, 14),  // Move 8
        ('black', 20, 14),  // Move 9
        ('white', 17, 16),  // Move 10 - This must be different! Check log again
        // Log says: [AI] >>> SELECTED: (17,16) score=445.0
        // But (17,16) already has Black stone from Move 1!
        // This suggests coordinates in log use different format
      ];

      // Let me try interpreting the coordinates differently
      // Maybe the format is (y, x) not (x, y)?
      // Or maybe the board starts from a different corner?

      // Let me just create the board state based on visual pattern
      // from looking at what captures 8 stones

      // From the actual game, we know:
      // - 8 white stones got captured at Move 19
      // - Black played at (18,12) to capture

      // For an enclosure to capture 8 stones, the white group must be
      // surrounded. Let me build the encirclement pattern properly.

      print('Building encirclement pattern that results in 8-stone capture...\n');

      // Black's encirclement (surrounding White)
      final blackStones = [
        // Top wall
        Position(17, 12), Position(18, 12), Position(19, 12),
        // Right wall
        Position(20, 13), Position(20, 14), Position(20, 15),
        // Bottom wall
        Position(19, 16), Position(18, 16), Position(17, 16),
        // Left wall
        Position(16, 15), Position(16, 14), Position(16, 13),
      ];

      // White stones (being captured)
      final whiteStones = [
        Position(17, 13), Position(18, 13), Position(19, 13),
        Position(17, 14), Position(18, 14), Position(19, 14),
        Position(17, 15), Position(18, 15),
      ];

      // Place stones - but leave one gap for Black to close
      // The capture point would be where the gap is
      // Let's leave (18,12) open as the capture point

      for (final pos in blackStones) {
        if (pos != Position(18, 12)) {
          // Leave gap at (18,12)
          board = board.placeStone(pos, StoneColor.black);
        }
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board state BEFORE Move 17 (Black plays (17,13)):');
      _printBoard(board, 14, 11, 22, 20);

      // Now simulate Black's Move 17
      board = board.placeStone(Position(17, 13), StoneColor.black);

      print('\nBoard state AFTER Move 17 (Black plays (17,13)):');
      _printBoard(board, 14, 11, 22, 20);

      // Check what happens if Black plays at (18,12)
      print('\nTesting potential capture at (18,12):');
      final captureTest = CaptureLogic.processMove(
        board,
        Position(18, 12),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('  If Black plays (18,12):');
      print('    Valid: ${captureTest.isValid}');
      print('    Captures: ${captureTest.captureResult?.captureCount ?? 0}');

      // Check what happens if Black plays at (18,13)
      print('\nTesting potential capture at (18,13):');
      final captureTest2 = CaptureLogic.processMove(
        board,
        Position(18, 13),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('  If Black plays (18,13):');
      print('    Valid: ${captureTest2.isValid}');
      print('    Captures: ${captureTest2.captureResult?.captureCount ?? 0}');

      // Now test AI's response
      print('\n--- AI ANALYSIS ---');
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(17, 13),
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // The AI should detect (18,12) as immediate capture block
      // If it doesn't, we have a bug
      if (captureTest.captureResult?.captureCount != null &&
          captureTest.captureResult!.captureCount > 0) {
        print('\n*** (18,12) IS a capture point! AI should block there ***');
      }

      // Now test what happens AFTER AI plays (18,13)
      print('\n--- AFTER AI PLAYS (18,13) ---');
      final boardAfterAI = board.placeStone(Position(18, 13), StoneColor.white);
      _printBoard(boardAfterAI, 14, 11, 22, 20);

      // Check if (18,12) NOW captures
      print('\nTesting (18,12) AFTER AI plays (18,13):');
      final captureTest3 = CaptureLogic.processMove(
        boardAfterAI,
        Position(18, 12),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('  If Black plays (18,12):');
      print('    Valid: ${captureTest3.isValid}');
      print('    Captures: ${captureTest3.captureResult?.captureCount ?? 0}');
      if (captureTest3.captureResult?.newEnclosures.isNotEmpty ?? false) {
        print('    New enclosures: ${captureTest3.captureResult!.newEnclosures.length}');
      }

      // The key insight: AI's move at (18,13) didn't PREVENT capture
      // It just delayed it by one move. The real blocking move was elsewhere.
      // Let's find what move WOULD prevent the capture at (18,12)

      print('\n--- FINDING THE REAL BLOCKING MOVE ---');
      // Test various positions to see which one prevents (18,12) from capturing
      final testPositions = [
        Position(18, 12), // Block directly
        Position(16, 13), // Escape route?
        Position(16, 12), // Another escape?
        Position(19, 12), // Different direction?
      ];

      for (final testPos in testPositions) {
        if (!board.isEmpty(testPos)) continue;

        final boardWithBlock = board.placeStone(testPos, StoneColor.white);
        // Now check if (18,12) still captures after White blocks at testPos
        final afterBlock = CaptureLogic.processMove(
          boardWithBlock,
          Position(18, 12),
          StoneColor.black,
          existingEnclosures: [],
        );

        final captures = afterBlock.captureResult?.captureCount ?? 0;
        final prevents = captures == 0 || captures < 8;
        print('  If AI plays $testPos first:');
        print('    Then Black (18,12) captures: $captures ${prevents ? "(BETTER!)" : ""}');
      }
    });

    test('Look for fork opportunities in early game', () {
      print('\n${'=' * 80}');
      print('FORK OPPORTUNITY ANALYSIS');
      print('${'=' * 80}\n');

      // Recreate early game state to find fork opportunities
      // Looking at moves 7-10 where AI might have had fork chances

      Board board = Board(size: 25);

      // State before Move 7
      final earlyMoves = [
        (Position(17, 16), StoneColor.black), // Move 1
        (Position(17, 15), StoneColor.white), // Move 2
        (Position(18, 16), StoneColor.black), // Move 3
        (Position(18, 15), StoneColor.white), // Move 4
        (Position(19, 15), StoneColor.black), // Move 5
        (Position(18, 14), StoneColor.white), // Move 6
      ];

      for (final (pos, color) in earlyMoves) {
        board = board.placeStone(pos, color);
      }

      print('Board state before Move 7:');
      _printBoard(board, 15, 13, 22, 19);

      // Check for positions that would threaten multiple black stones
      print('\nAnalyzing fork opportunities for White:');

      // A "fork" is a position where placing creates two separate threats
      // In this game, that means creating two positions where we could capture

      final candidates = <Position>[];
      for (int x = 15; x <= 22; x++) {
        for (int y = 13; y <= 19; y++) {
          final pos = Position(x, y);
          if (!board.isEmpty(pos)) continue;

          // Simulate placing white stone
          final newBoard = board.placeStone(pos, StoneColor.white);

          // Count how many black groups become threatened
          int threatenedGroups = 0;

          // Check each adjacent position for black stones
          for (final adj in pos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (board.getStoneAt(adj) == StoneColor.black) {
              // Check if this black stone's group becomes more vulnerable
              final escapeCheck = _simpleEscapeCheck(newBoard, adj, StoneColor.black);
              if (escapeCheck <= 3) {
                threatenedGroups++;
              }
            }
          }

          if (threatenedGroups >= 2) {
            candidates.add(pos);
            print('  Fork candidate: $pos (threatens $threatenedGroups groups)');
          }
        }
      }

      if (candidates.isEmpty) {
        print('  No clear fork opportunities found at this stage');
      }
    });
  });
}

/// Simple escape check - count edge-reachable empty cells
int _simpleEscapeCheck(Board board, Position start, StoneColor color) {
  final visited = <Position>{};
  final toVisit = <Position>[start];
  int edgeCount = 0;

  while (toVisit.isNotEmpty) {
    final current = toVisit.removeLast();
    if (visited.contains(current)) continue;
    if (!board.isValidPosition(current)) continue;

    final stone = board.getStoneAt(current);
    if (stone != null && stone != color) continue;

    visited.add(current);

    // Check if on edge
    if (current.x == 0 || current.y == 0 ||
        current.x == board.size - 1 || current.y == board.size - 1) {
      if (board.isEmpty(current)) {
        edgeCount++;
      }
    }

    for (final adj in current.adjacentPositions) {
      if (!visited.contains(adj) && board.isValidPosition(adj)) {
        if (board.isEmpty(adj) || board.getStoneAt(adj) == color) {
          toVisit.add(adj);
        }
      }
    }
  }

  return edgeCount;
}

void _printBoard(Board board, int startX, int startY, int endX, int endY) {
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
