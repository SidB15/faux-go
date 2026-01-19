enum GameMode {
  fixedMoves,
  captureTarget;

  String get displayName {
    switch (this) {
      case GameMode.fixedMoves:
        return 'Fixed Moves';
      case GameMode.captureTarget:
        return 'Capture Target';
    }
  }

  String get description {
    switch (this) {
      case GameMode.fixedMoves:
        return 'Game ends after a set number of moves';
      case GameMode.captureTarget:
        return 'First to capture target stones wins';
    }
  }

  List<int> get targetOptions {
    switch (this) {
      case GameMode.fixedMoves:
        return [100, 200, 500];
      case GameMode.captureTarget:
        return [10, 25, 50];
    }
  }
}

enum GameStatus {
  setup,
  playing,
  finished;
}
