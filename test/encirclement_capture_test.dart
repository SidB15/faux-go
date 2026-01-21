// Encirclement Capture Detection Test
// Tests that AI correctly detects when opponent can complete an enclosure
//
// Run with: flutter test test/encirclement_capture_test.dart --reporter expanded

import 'package:flutter_test/flutter_test.dart';
import 'package:edgeline/models/models.dart';
import 'package:edgeline/logic/ai_engine.dart';
import 'package:edgeline/logic/capture_logic.dart';

void main() {
  group('Encirclement Capture Detection Tests', () {
    late AiEngine engine;

    setUp(() {
      engine = AiEngine();
      AiEngine.resetPOICache();
    });

    test('AI should detect single-gap enclosure completion', () {
      print('\n${'=' * 80}');
      print('SCENARIO: Single Gap Enclosure');
      print('${'=' * 80}\n');

      // Create a board where Black has almost completed an enclosure
      // with ONE gap that would capture White stones
      //
      // Board visualization:
      //     14 15 16 17 18 19 20 21
      // 11   .  .  .  .  .  .  .  .
      // 12   .  .  B  B  .  B  B  .   <- Gap at (18,12)
      // 13   .  .  B  W  W  W  B  .
      // 14   .  .  B  W  W  W  B  .
      // 15   .  .  B  W  W  W  B  .
      // 16   .  .  B  B  B  B  B  .
      // 17   .  .  .  .  .  .  .  .

      Board board = Board(size: 25);

      // Black's encirclement wall (with gap at 18,12)
      final blackStones = [
        // Top wall (with gap)
        Position(16, 12), Position(17, 12), // Gap at (18,12)
        Position(19, 12), Position(20, 12),
        // Left wall
        Position(16, 13), Position(16, 14), Position(16, 15),
        // Right wall
        Position(20, 13), Position(20, 14), Position(20, 15),
        // Bottom wall
        Position(16, 16), Position(17, 16), Position(18, 16),
        Position(19, 16), Position(20, 16),
      ];

      // White stones inside (to be captured)
      final whiteStones = [
        Position(17, 13), Position(18, 13), Position(19, 13),
        Position(17, 14), Position(18, 14), Position(19, 14),
        Position(17, 15), Position(18, 15), Position(19, 15),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup (gap at 18,12):');
      _printBoard(board, 14, 10, 22, 18);

      // Verify that (18,12) would capture
      print('\nVerifying capture at (18,12):');
      final captureResult = CaptureLogic.processMove(
        board,
        Position(18, 12),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('  If Black plays (18,12):');
      print('    Valid: ${captureResult.isValid}');
      print('    Captures: ${captureResult.captureResult?.captureCount ?? 0}');

      expect(captureResult.captureResult?.captureCount ?? 0, greaterThan(0),
          reason: 'Black playing (18,12) should capture White stones');

      // Now test AI's response
      print('\n--- AI ANALYSIS ---');
      final opponentLastMove = Position(17, 12); // Black just played the second-to-last stone
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: opponentLastMove,
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // AI MUST play (18,12) to prevent capture
      expect(aiMove, equals(Position(18, 12)),
          reason: 'AI must block at (18,12) to prevent enclosure capture');
    });

    test('AI should detect two-gap enclosure - block the more dangerous one', () {
      print('\n${'=' * 80}');
      print('SCENARIO: Two Gap Enclosure');
      print('${'=' * 80}\n');

      // Similar setup but with TWO gaps
      // AI should still identify both as critical and pick one

      Board board = Board(size: 25);

      // Black's encirclement wall (with gaps at 17,12 and 19,12)
      final blackStones = [
        // Top wall (with gaps)
        Position(16, 12), // Gap at (17,12), Gap at (18,12),
        Position(19, 12), Position(20, 12),
        // Left wall
        Position(16, 13), Position(16, 14), Position(16, 15),
        // Right wall
        Position(20, 13), Position(20, 14), Position(20, 15),
        // Bottom wall
        Position(16, 16), Position(17, 16), Position(18, 16),
        Position(19, 16), Position(20, 16),
      ];

      // White stones inside
      final whiteStones = [
        Position(17, 13), Position(18, 13), Position(19, 13),
        Position(17, 14), Position(18, 14), Position(19, 14),
        Position(17, 15), Position(18, 15), Position(19, 15),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup (gaps at 17,12 and 18,12):');
      _printBoard(board, 14, 10, 22, 18);

      // Check both gaps
      print('\nVerifying gaps:');
      for (final gap in [Position(17, 12), Position(18, 12)]) {
        final result = CaptureLogic.processMove(
          board,
          gap,
          StoneColor.black,
          existingEnclosures: [],
        );
        print('  Gap $gap - Would capture: ${result.captureResult?.captureCount ?? 0}');
      }

      // Test AI's response
      print('\n--- AI ANALYSIS ---');
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(16, 12),
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // AI should block one of the gaps
      final blocksGap = aiMove == Position(17, 12) || aiMove == Position(18, 12);
      expect(blocksGap, isTrue,
          reason: 'AI should block one of the enclosure gaps');
    });

    test('Two-move lookahead: AI should detect threat requiring opponent two moves', () {
      print('\n${'=' * 80}');
      print('SCENARIO: Two-Move Threat Detection');
      print('${'=' * 80}\n');

      // In this scenario, Black needs TWO more moves to capture
      // The AI should still recognize the danger and try to escape/block

      Board board = Board(size: 25);

      // Almost-encirclement with 2 gaps
      final blackStones = [
        // Top wall (two gaps)
        Position(16, 12), Position(17, 12), // Gaps at (18,12) and (19,12)
        Position(20, 12),
        // Left wall
        Position(16, 13), Position(16, 14), Position(16, 15),
        // Right wall
        Position(20, 13), Position(20, 14), Position(20, 15),
        // Bottom wall
        Position(16, 16), Position(17, 16), Position(18, 16),
        Position(19, 16), Position(20, 16),
      ];

      final whiteStones = [
        Position(17, 13), Position(18, 13), Position(19, 13),
        Position(17, 14), Position(18, 14), Position(19, 14),
        Position(17, 15), Position(18, 15), Position(19, 15),
      ];

      for (final pos in blackStones) {
        board = board.placeStone(pos, StoneColor.black);
      }
      for (final pos in whiteStones) {
        board = board.placeStone(pos, StoneColor.white);
      }

      print('Board setup (2 gaps in wall):');
      _printBoard(board, 14, 10, 22, 18);

      // Neither gap alone captures (need both filled)
      print('\nVerifying no single-move capture:');
      for (final gap in [Position(18, 12), Position(19, 12)]) {
        final result = CaptureLogic.processMove(
          board,
          gap,
          StoneColor.black,
          existingEnclosures: [],
        );
        print('  Single move at $gap captures: ${result.captureResult?.captureCount ?? 0}');
      }

      // But if Black plays one, THEN the other captures
      print('\nVerifying two-move capture:');
      final boardAfterFirst = board.placeStone(Position(18, 12), StoneColor.black);
      final secondMoveResult = CaptureLogic.processMove(
        boardAfterFirst,
        Position(19, 12),
        StoneColor.black,
        existingEnclosures: [],
      );
      print('  After (18,12), then (19,12) captures: ${secondMoveResult.captureResult?.captureCount ?? 0}');

      // AI should recognize this and either:
      // 1. Block one of the gaps
      // 2. Try to escape/extend outward
      print('\n--- AI ANALYSIS ---');
      final aiMove = engine.calculateMove(
        board,
        StoneColor.white,
        AiLevel.level10,
        opponentLastMove: Position(17, 12),
        enclosures: [],
      );

      print('\nAI selected move: $aiMove');

      // Check if AI is blocking or escaping
      final isBlocking = aiMove == Position(18, 12) || aiMove == Position(19, 12);
      final isEscaping = aiMove!.y < 12; // Moving upward to escape
      print('AI strategy: ${isBlocking ? "BLOCKING" : isEscaping ? "ESCAPING" : "OTHER"}');
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
