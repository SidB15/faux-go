// Critical Block Priority Test
// Tests that AI correctly prioritizes critical blocks that DIRECTLY prevent capture
// over critical blocks that are less urgent
//
// Run with: flutter test test/critical_block_priority_test.dart --reporter expanded

import 'package:flutter_test/flutter_test.dart';
import 'package:edgeline/models/models.dart';
import 'package:edgeline/logic/ai_engine.dart';
import 'package:edgeline/logic/capture_logic.dart';

void main() {
  group('Critical Block Priority Tests', () {
    late AiEngine engine;

    setUp(() {
      engine = AiEngine();
      AiEngine.resetPOICache();
    });

    test('Scenario: AI should block immediate capture threat at (6,8)', () {
      print('\n${'=' * 80}');
      print('SCENARIO: Immediate Capture Threat');
      print('${'=' * 80}\n');

      // Recreate the exact board state before Move 8
      // Black: (6,9), (7,9), (8,8), (7,7)
      // White: (7,8), (9,9), (8,9)
      //
      // Board visualization:
      //     5  6  7  8  9 10
      //  6  .  .  .  .  .  .
      //  7  .  .  B  .  .  .
      //  8  .  .  W  B  .  .
      //  9  .  B  B  W  W  .
      // 10  .  .  .  .  .  .
      //
      // Black's last move: (7,7)
      // Critical positions detected: {(6,8), (8,10)}
      //
      // KEY: (6,8) creates an enclosure and CAPTURES the white stone at (7,8)
      //      (8,10) is also "critical" but doesn't prevent immediate capture
      //
      // AI MUST play (6,8) to prevent capture!

      Board board = Board(size: 15);

      // Place Black stones
      final blackStones = [
        Position(6, 9),  // Part of encirclement
        Position(7, 9),  // Part of encirclement
        Position(8, 8),  // Key stone threatening (7,8)
        Position(7, 7),  // Last move - completes threat
      ];

      // Place White stones
      final whiteStones = [
        Position(7, 8),  // THIS STONE IS ABOUT TO BE CAPTURED!
        Position(9, 9),  // Separate group
        Position(8, 9),  // Connected to (9,9)
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup:');
      _printBoard(board, 4, 5, 12, 12);

      final opponentLastMove = Position(7, 7);
      print('\nBlack\'s last move: $opponentLastMove');

      // Verify that (6,8) would capture if Black plays there
      final blackCaptureResult = CaptureLogic.processMove(
        board,
        Position(6, 8),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('\nIf BLACK plays (6,8):');
      print('  Valid: ${blackCaptureResult.isValid}');
      print('  Captures: ${blackCaptureResult.captureResult?.captureCount ?? 0}');

      expect(blackCaptureResult.captureResult?.captureCount ?? 0, greaterThan(0),
          reason: 'Black playing (6,8) should capture White stone(s)');

      // Now test AI's response
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // AI MUST play (6,8) to prevent capture
      expect(aiMove, equals(Position(6, 8)),
          reason: 'AI must play (6,8) to prevent immediate capture of its stone at (7,8)');

      if (aiMove == Position(6, 8)) {
        print('\n✓ SUCCESS: AI correctly blocked the capture threat!');
      } else {
        print('\n✗ FAILURE: AI played $aiMove instead of (6,8)');
        print('  This allows Black to capture White\'s stone at (7,8)!');
      }
    });

    test('Scenario 2: Similar position with earlier setup', () {
      print('\n${'=' * 80}');
      print('SCENARIO 2: One Move Earlier');
      print('${'=' * 80}\n');

      // Position one move before - Black about to play (7,7)
      // After (7,7), White must respond at (6,8)
      //
      // Board:
      //     5  6  7  8  9 10
      //  7  .  .  .  .  .  .
      //  8  .  .  W  B  .  .
      //  9  .  B  B  W  W  .
      // 10  .  .  .  .  .  .

      Board board = Board(size: 15);

      final blackStones = [
        Position(6, 9),
        Position(7, 9),
        Position(8, 8),
      ];

      final whiteStones = [
        Position(7, 8),
        Position(9, 9),
        Position(8, 9),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup (before Black plays (7,7)):');
      _printBoard(board, 4, 5, 12, 12);

      // Simulate Black playing (7,7)
      board = board.placeStone(Position(7, 7), StoneColor.black);

      print('\nAfter Black plays (7,7):');
      _printBoard(board, 4, 5, 12, 12);

      final opponentLastMove = Position(7, 7);

      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI response: $aiMove');

      expect(aiMove, equals(Position(6, 8)),
          reason: 'AI must block at (6,8) to prevent capture');
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
