import '../models/models.dart';

class WinCheckResult {
  final bool isGameOver;
  final StoneColor? winner;
  final String? reason;

  WinCheckResult({
    required this.isGameOver,
    this.winner,
    this.reason,
  });

  factory WinCheckResult.notOver() {
    return WinCheckResult(isGameOver: false);
  }

  factory WinCheckResult.gameOver({
    StoneColor? winner,
    required String reason,
  }) {
    return WinCheckResult(
      isGameOver: true,
      winner: winner,
      reason: reason,
    );
  }
}

class WinChecker {
  /// Check if game is over based on current state
  static WinCheckResult checkWinCondition(GameState state) {
    switch (state.settings.mode) {
      case GameMode.fixedMoves:
        return _checkFixedMovesWin(state);
      case GameMode.captureTarget:
        return _checkCaptureTargetWin(state);
    }
  }

  /// Check win condition for fixed moves mode
  static WinCheckResult _checkFixedMovesWin(GameState state) {
    // Check if move limit reached
    if (state.moveCount >= state.settings.targetValue) {
      final winner = _determineWinnerByCaptures(state);
      return WinCheckResult.gameOver(
        winner: winner,
        reason: winner != null
            ? '${winner.displayName} wins with more captures!'
            : 'Game ended in a tie!',
      );
    }

    // Check for double pass (both players pass consecutively)
    if (state.consecutivePasses >= 2) {
      final winner = _determineWinnerByCaptures(state);
      return WinCheckResult.gameOver(
        winner: winner,
        reason: winner != null
            ? 'Both players passed. ${winner.displayName} wins!'
            : 'Both players passed. Game ended in a tie!',
      );
    }

    return WinCheckResult.notOver();
  }

  /// Check win condition for capture target mode
  static WinCheckResult _checkCaptureTargetWin(GameState state) {
    final target = state.settings.targetValue;

    if (state.blackCaptures >= target) {
      return WinCheckResult.gameOver(
        winner: StoneColor.black,
        reason: 'Black reached $target captures!',
      );
    }

    if (state.whiteCaptures >= target) {
      return WinCheckResult.gameOver(
        winner: StoneColor.white,
        reason: 'White reached $target captures!',
      );
    }

    // Check for double pass
    if (state.consecutivePasses >= 2) {
      final winner = _determineWinnerByCaptures(state);
      return WinCheckResult.gameOver(
        winner: winner,
        reason: winner != null
            ? 'Both players passed. ${winner.displayName} wins!'
            : 'Both players passed. Game ended in a tie!',
      );
    }

    return WinCheckResult.notOver();
  }

  /// Determine winner by comparing captures
  static StoneColor? _determineWinnerByCaptures(GameState state) {
    if (state.blackCaptures > state.whiteCaptures) {
      return StoneColor.black;
    } else if (state.whiteCaptures > state.blackCaptures) {
      return StoneColor.white;
    }
    return null; // Tie
  }
}
