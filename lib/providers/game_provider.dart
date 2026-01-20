import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/logic.dart';
import '../models/models.dart';

/// Provider for game settings (used in setup screen)
final gameSettingsProvider = StateProvider<GameSettings>((ref) {
  return GameSettings.defaultSettings;
});

/// Provider for game state
final gameStateProvider =
    StateNotifierProvider<GameNotifier, GameState?>((ref) {
  return GameNotifier();
});

/// Provider for game count (for interstitial ad frequency)
final gameCountProvider = StateProvider<int>((ref) => 0);

class GameNotifier extends StateNotifier<GameState?> {
  GameNotifier() : super(null);

  /// Maximum number of undo states to keep (prevents memory bloat)
  static const int _maxHistorySize = 50;

  /// Game logger instance
  final GameLogger _logger = GameLogger();

  /// Start a new game with the given settings
  void startGame(GameSettings settings) {
    state = GameState.initial(settings);
    _logger.startGame(settings);
  }

  /// Place a stone at the given position
  /// [isAiMove] indicates if this move was made by the AI (for logging)
  bool placeStone(Position pos, {bool isAiMove = false}) {
    if (state == null || state!.status != GameStatus.playing) {
      return false;
    }

    final currentState = state!;
    final result = CaptureLogic.processMove(
      currentState.board,
      pos,
      currentState.currentPlayer,
      existingEnclosures: currentState.enclosures,
    );

    if (!result.isValid) {
      return false;
    }

    // Calculate new captures
    final capturedCount = result.captureResult?.captureCount ?? 0;
    int newBlackCaptures = currentState.blackCaptures;
    int newWhiteCaptures = currentState.whiteCaptures;

    debugPrint('Move at $pos by ${currentState.currentPlayer}, captured: $capturedCount');

    if (currentState.currentPlayer == StoneColor.black) {
      newBlackCaptures += capturedCount;
    } else {
      newWhiteCaptures += capturedCount;
    }

    debugPrint('Black captures: $newBlackCaptures, White captures: $newWhiteCaptures');

    // Log the move
    final enclosuresCreated = result.captureResult?.newEnclosures.length ?? 0;
    _logger.logMove(
      moveNumber: currentState.moveCount + 1,
      player: currentState.currentPlayer,
      position: pos,
      capturedCount: capturedCount,
      blackTotalCaptures: newBlackCaptures,
      whiteTotalCaptures: newWhiteCaptures,
      enclosuresCreated: enclosuresCreated,
      isAiMove: isAiMove,
      board: result.newBoard!,
    );

    // Limit history size to prevent memory bloat
    List<Board> newHistory;
    if (currentState.history.length >= _maxHistorySize) {
      // Drop oldest entries, keep most recent ones
      newHistory = [...currentState.history.skip(1), currentState.board];
    } else {
      newHistory = [...currentState.history, currentState.board];
    }

    // Update enclosures - add new ones from this capture
    final newEnclosures = [...currentState.enclosures];
    if (result.captureResult != null && result.captureResult!.newEnclosures.isNotEmpty) {
      newEnclosures.addAll(result.captureResult!.newEnclosures);
      debugPrint('New enclosures created: ${result.captureResult!.newEnclosures.length}');
    }

    // Handle ghost stones for captured pieces
    // Ghosts persist until the same player moves again (full turn cycle)
    final newCapturedPositions = result.captureResult?.capturedPositions ?? const <Position>{};
    final hasCapturedThisTurn = newCapturedPositions.isNotEmpty;

    // Determine what ghost positions to show
    Set<Position> ghostPositions;
    StoneColor? ghostColor;
    StoneColor? ghostCapturedBy;

    if (hasCapturedThisTurn) {
      // New capture this turn - show these ghosts
      ghostPositions = newCapturedPositions;
      ghostColor = currentState.currentPlayer.opponent; // Captured stones were opponent's
      ghostCapturedBy = currentState.currentPlayer;
    } else if (currentState.capturedByPlayer == currentState.currentPlayer) {
      // Same player who captured is moving again - clear ghosts
      ghostPositions = const {};
      ghostColor = null;
      ghostCapturedBy = null;
    } else {
      // Keep existing ghosts (opponent hasn't moved yet or no ghosts exist)
      ghostPositions = currentState.lastCapturedPositions;
      ghostColor = currentState.lastCapturedColor;
      ghostCapturedBy = currentState.capturedByPlayer;
    }

    // Create new state
    var newState = currentState.copyWith(
      board: result.newBoard,
      currentPlayer: currentState.currentPlayer.opponent,
      moveCount: currentState.moveCount + 1,
      blackCaptures: newBlackCaptures,
      whiteCaptures: newWhiteCaptures,
      lastMove: pos,
      history: newHistory,
      consecutivePasses: 0,
      enclosures: newEnclosures,
      lastCapturedPositions: ghostPositions,
      lastCapturedColor: ghostColor,
      clearCapturedColor: ghostColor == null,
      capturedByPlayer: ghostCapturedBy,
      clearCapturedByPlayer: ghostCapturedBy == null,
    );

    // Check win condition
    final winResult = WinChecker.checkWinCondition(newState);
    if (winResult.isGameOver) {
      newState = newState.copyWith(
        status: GameStatus.finished,
        winner: winResult.winner,
      );
      // Log game end
      _logger.endGame(
        winner: winResult.winner,
        endReason: _getEndReason(newState),
      );
    }

    state = newState;
    return true;
  }

  /// Get the reason the game ended
  String _getEndReason(GameState gameState) {
    if (gameState.consecutivePasses >= 2) {
      return 'double_pass';
    }
    if (gameState.settings.mode == GameMode.fixedMoves &&
        gameState.moveCount >= gameState.settings.targetValue) {
      return 'move_limit_reached';
    }
    if (gameState.settings.mode == GameMode.captureTarget) {
      if (gameState.blackCaptures >= gameState.settings.targetValue) {
        return 'capture_target_black';
      }
      if (gameState.whiteCaptures >= gameState.settings.targetValue) {
        return 'capture_target_white';
      }
    }
    return 'unknown';
  }

  /// Pass turn
  /// [isAiMove] indicates if this pass was made by the AI (for logging)
  void pass({bool isAiMove = false}) {
    if (state == null || state!.status != GameStatus.playing) {
      return;
    }

    final currentState = state!;

    // Log the pass
    _logger.logPass(
      moveNumber: currentState.moveCount + 1,
      player: currentState.currentPlayer,
      isAiMove: isAiMove,
    );

    // Clear ghosts if the player who captured is passing
    final shouldClearGhosts = currentState.capturedByPlayer == currentState.currentPlayer;

    var newState = currentState.copyWith(
      currentPlayer: currentState.currentPlayer.opponent,
      moveCount: currentState.moveCount + 1,
      consecutivePasses: currentState.consecutivePasses + 1,
      clearLastMove: true,
      lastCapturedPositions: shouldClearGhosts ? const {} : null,
      clearCapturedColor: shouldClearGhosts,
      clearCapturedByPlayer: shouldClearGhosts,
    );

    // Check win condition (double pass ends game)
    final winResult = WinChecker.checkWinCondition(newState);
    if (winResult.isGameOver) {
      newState = newState.copyWith(
        status: GameStatus.finished,
        winner: winResult.winner,
      );
      // Log game end
      _logger.endGame(
        winner: winResult.winner,
        endReason: _getEndReason(newState),
      );
    }

    state = newState;
  }

  /// Undo last move
  void undo() {
    if (state == null || !state!.canUndo) {
      return;
    }

    final currentState = state!;
    final previousBoard = currentState.history.last;
    final newHistory = currentState.history.sublist(
      0,
      currentState.history.length - 1,
    );

    // Note: We can't accurately restore captures on undo
    // For simplicity, we just restore the board and switch player back
    state = currentState.copyWith(
      board: previousBoard,
      currentPlayer: currentState.currentPlayer.opponent,
      moveCount: currentState.moveCount - 1,
      history: newHistory,
      clearLastMove: true,
      consecutivePasses: 0,
      lastCapturedPositions: const {},
      clearCapturedColor: true,
      clearCapturedByPlayer: true,
    );
  }

  /// Reset game
  void resetGame() {
    state = null;
  }
}
