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

  /// Start a new game with the given settings
  void startGame(GameSettings settings) {
    state = GameState.initial(settings);
  }

  /// Place a stone at the given position
  bool placeStone(Position pos) {
    if (state == null || state!.status != GameStatus.playing) {
      return false;
    }

    final currentState = state!;
    final result = CaptureLogic.processMove(
      currentState.board,
      pos,
      currentState.currentPlayer,
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

    // Create new state
    var newState = currentState.copyWith(
      board: result.newBoard,
      currentPlayer: currentState.currentPlayer.opponent,
      moveCount: currentState.moveCount + 1,
      blackCaptures: newBlackCaptures,
      whiteCaptures: newWhiteCaptures,
      lastMove: pos,
      history: [...currentState.history, currentState.board],
      consecutivePasses: 0,
    );

    // Check win condition
    final winResult = WinChecker.checkWinCondition(newState);
    if (winResult.isGameOver) {
      newState = newState.copyWith(
        status: GameStatus.finished,
        winner: winResult.winner,
      );
    }

    state = newState;
    return true;
  }

  /// Pass turn
  void pass() {
    if (state == null || state!.status != GameStatus.playing) {
      return;
    }

    final currentState = state!;

    var newState = currentState.copyWith(
      currentPlayer: currentState.currentPlayer.opponent,
      moveCount: currentState.moveCount + 1,
      consecutivePasses: currentState.consecutivePasses + 1,
      clearLastMove: true,
    );

    // Check win condition (double pass ends game)
    final winResult = WinChecker.checkWinCondition(newState);
    if (winResult.isGameOver) {
      newState = newState.copyWith(
        status: GameStatus.finished,
        winner: winResult.winner,
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
    );
  }

  /// Reset game
  void resetGame() {
    state = null;
  }
}
