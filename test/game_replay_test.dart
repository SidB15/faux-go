// Game Replay Test
// Tests AI move decisions at specific game positions
// Based on actual game log where AI lost 8 stones at Move 19 (capture at 18,12)
//
// Run with: flutter test test/game_replay_test.dart --reporter expanded

import 'package:flutter_test/flutter_test.dart';
import 'package:edgeline/models/models.dart';
import 'package:edgeline/logic/ai_engine.dart';
import 'package:edgeline/logic/capture_logic.dart';

void main() {
  group('Game Replay Analysis', () {
    late AiEngine engine;

    setUp(() {
      engine = AiEngine();
      AiEngine.resetPOICache();
    });

    test('Replay Move 17-19: AI should detect capture threat at (18,12)', () {
      print('\n${'=' * 80}');
      print('GAME REPLAY: Move 17-19 Analysis');
      print('${'=' * 80}\n');

      // Reconstruct board at Move 17
      // From game log:
      // Move 1: Black (7,7)
      // Move 2: White (9,9)
      // Move 3: Black (10,9)
      // Move 4: White (11,9)
      // Move 5: Black (11,10)
      // Move 6: White (12,9)
      // Move 7: Black (12,10)
      // Move 8: White (12,8)
      // Move 9: Black (13,8)
      // Move 10: White (13,9)
      // Move 11: Black (13,10)
      // Move 12: White (14,10)
      // Move 13: Black (13,11)
      // Move 14: White (13,7)
      // Move 15: Black (12,7)
      // Move 16: White (12,6)
      // Move 17: Black (11,7) - this triggers AI response at Move 18

      Board board = Board(size: 25);

      // Black moves (odd numbered)
      final blackMoves = [
        Position(7, 7),   // Move 1
        Position(10, 9),  // Move 3
        Position(11, 10), // Move 5
        Position(12, 10), // Move 7
        Position(13, 8),  // Move 9
        Position(13, 10), // Move 11
        Position(13, 11), // Move 13
        Position(12, 7),  // Move 15
        Position(11, 7),  // Move 17
      ];

      // White moves (even numbered)
      final whiteMoves = [
        Position(9, 9),   // Move 2
        Position(11, 9),  // Move 4
        Position(12, 9),  // Move 6
        Position(12, 8),  // Move 8
        Position(13, 9),  // Move 10
        Position(14, 10), // Move 12
        Position(13, 7),  // Move 14
        Position(12, 6),  // Move 16
      ];

      for (final pos in blackMoves) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteMoves) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board after Move 17 (Black played 11,7):');
      _printBoard(board, 6, 5, 16, 14);

      // What does AI detect at this point?
      print('\n--- AI ANALYSIS FOR MOVE 18 ---');
      final move18 = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(11, 7),
        enclosures: [],
      );
      print('AI selected Move 18: $move18');

      // Check what would happen if opponent plays various positions
      print('\n--- THREAT ANALYSIS ---');
      final threatsToCheck = [
        Position(18, 12), // Actual capture position from game log
        Position(18, 13),
        Position(11, 8),
        Position(10, 7),
        Position(14, 9),
      ];

      for (final threat in threatsToCheck) {
        if (!board.isValidPosition(threat) || !board.isEmpty(threat)) continue;

        final result = CaptureLogic.processMove(
          board,
          threat,
          StoneColor.black,
          existingEnclosures: [],
        );
        print('If Black plays $threat:');
        print('  Valid: ${result.isValid}');
        print('  Captures: ${result.captureResult?.captureCount ?? 0}');
        if (result.captureResult?.newEnclosures.isNotEmpty ?? false) {
          print('  Creates enclosure: YES');
        }
      }
    });

    test('Test individual move scenarios from failed game', () {
      print('\n${'=' * 80}');
      print('INDIVIDUAL MOVE SCENARIO ANALYSIS');
      print('${'=' * 80}\n');

      // Simpler scenario: Create position just before capture
      // Based on game log, by move 17-18 there should be a forming encirclement

      Board board = Board(size: 25);

      // Set up a cleaner test scenario where AI is about to be captured
      // Create almost-complete encirclement of white stones

      // Black forming encirclement around white group
      final blackStones = [
        // Top wall
        Position(10, 6), Position(11, 6), Position(12, 6), Position(13, 6),
        // Left side
        Position(9, 7), Position(9, 8), Position(9, 9), Position(9, 10),
        // Right side
        Position(14, 7), Position(14, 8), Position(14, 9), Position(14, 10),
        // Bottom (with gap at 12,11)
        Position(10, 11), Position(11, 11), /* gap at 12,11 */ Position(13, 11),
      ];

      // White stones trapped inside
      final whiteStones = [
        Position(11, 8), Position(12, 8),
        Position(11, 9), Position(12, 9),
        Position(11, 10), Position(12, 10),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup - encirclement with gap at (12,11):');
      _printBoard(board, 8, 4, 16, 13);

      // Verify gap is the capture point
      print('\n--- VERIFYING CAPTURE AT (12,11) ---');
      final captureResult = CaptureLogic.processMove(
        board,
        Position(12, 11),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('If Black plays (12,11):');
      print('  Valid: ${captureResult.isValid}');
      print('  Captures: ${captureResult.captureResult?.captureCount ?? 0}');

      // Now test AI response
      print('\n--- AI ANALYSIS ---');
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(13, 11), // Black just played bottom-right corner
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // AI MUST play (12,11) to prevent capture
      if ((captureResult.captureResult?.captureCount ?? 0) > 0) {
        expect(aiMove, equals(Position(12, 11)),
            reason: 'AI must block at (12,11) to prevent enclosure capture');
      }
    });

    test('Edge-case: Capture point far from AI stones', () {
      print('\n${'=' * 80}');
      print('EDGE CASE: Far capture point');
      print('${'=' * 80}\n');

      // Test case where capture point is 4+ cells away from nearest AI stone
      // This tests if searchRadius=3 in _findWallGapCapturePositions is sufficient

      Board board = Board(size: 25);

      // Create a larger encirclement where the gap is far from AI stones
      final blackStones = [
        // Top wall (long)
        Position(8, 5), Position(9, 5), Position(10, 5), Position(11, 5),
        Position(12, 5), Position(13, 5), Position(14, 5),
        // Left side
        Position(7, 6), Position(7, 7), Position(7, 8), Position(7, 9),
        Position(7, 10), Position(7, 11),
        // Right side
        Position(15, 6), Position(15, 7), Position(15, 8), Position(15, 9),
        Position(15, 10), Position(15, 11),
        // Bottom (gap at 12,12 - far from white stones at center)
        Position(8, 12), Position(9, 12), Position(10, 12), Position(11, 12),
        /* gap at 12,12 */ Position(13, 12), Position(14, 12),
      ];

      // White stones concentrated at top-center (far from gap)
      final whiteStones = [
        Position(10, 7), Position(11, 7), Position(12, 7),
        Position(10, 8), Position(11, 8), Position(12, 8),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup - gap at (12,12) is 4 cells from nearest white stone:');
      _printBoard(board, 5, 3, 17, 14);

      // Calculate distance from gap to nearest white stone
      final gap = Position(12, 12);
      int minDistance = 999;
      for (final white in whiteStones) {
        final dist = (gap.x - white.x).abs() + (gap.y - white.y).abs();
        if (dist < minDistance) minDistance = dist;
      }
      print('Distance from gap (12,12) to nearest white stone: $minDistance');

      // Verify gap is capture point
      print('\n--- VERIFYING CAPTURE ---');
      final captureResult = CaptureLogic.processMove(
        board,
        gap,
        StoneColor.black,
        existingEnclosures: [],
      );
      print('If Black plays $gap:');
      print('  Captures: ${captureResult.captureResult?.captureCount ?? 0}');

      // Test AI response
      print('\n--- AI ANALYSIS ---');
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(13, 12),
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // Check if AI found the far gap
      if ((captureResult.captureResult?.captureCount ?? 0) > 0) {
        if (aiMove == gap) {
          print('SUCCESS: AI found far capture point!');
        } else {
          print('ISSUE: AI missed far capture point at $gap');
          print('searchRadius may need to be increased from 3 to $minDistance');
        }
      }
    });

    test('Detection timing: AI should detect threat BEFORE it becomes urgent', () {
      print('\n${'=' * 80}');
      print('TIMING TEST: Early threat detection');
      print('${'=' * 80}\n');

      // Test if AI detects threat when there are still 2 gaps in encirclement
      // vs when there's only 1 gap (imminent)

      Board board = Board(size: 25);

      // Encirclement with 2 gaps
      final blackStones = [
        Position(10, 6), Position(11, 6), Position(12, 6),
        Position(9, 7), Position(9, 8), Position(9, 9),
        Position(13, 7), Position(13, 8), Position(13, 9),
        Position(10, 10), /* gap at 11,10 and 12,10 */
      ];

      final whiteStones = [
        Position(10, 8), Position(11, 8), Position(12, 8),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('PHASE 1: Two gaps at (11,10) and (12,10)');
      _printBoard(board, 7, 4, 15, 12);

      final move1 = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(10, 10),
        enclosures: [],
      );
      print('AI move with 2 gaps: $move1');

      // Now close one gap
      board = board.placeStone(Position(11, 10), StoneColor.black);

      print('\nPHASE 2: One gap remaining at (12,10)');
      _printBoard(board, 7, 4, 15, 12);

      AiEngine.resetPOICache();
      final move2 = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(11, 10),
        enclosures: [],
      );
      print('AI move with 1 gap: $move2');

      // Verify that (12,10) is indeed the capture point now
      final captureResult = CaptureLogic.processMove(
        board,
        Position(12, 10),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('\nIf Black plays (12,10): ${captureResult.captureResult?.captureCount ?? 0} captures');

      if ((captureResult.captureResult?.captureCount ?? 0) > 0) {
        expect(move2, equals(Position(12, 10)),
            reason: 'AI must block immediate capture threat');
      }
    });
  });
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
