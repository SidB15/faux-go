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

enum OpponentType {
  cpu,
  human;

  String get displayName {
    switch (this) {
      case OpponentType.cpu:
        return 'CPU';
      case OpponentType.human:
        return 'Human';
    }
  }
}

enum AiLevel {
  level1(1, 'Beginner', 0.1),
  level2(2, 'Novice', 0.2),
  level3(3, 'Easy', 0.3),
  level4(4, 'Normal', 0.4),
  level5(5, 'Intermediate', 0.5),
  level6(6, 'Challenging', 0.6),
  level7(7, 'Hard', 0.7),
  level8(8, 'Expert', 0.8),
  level9(9, 'Master', 0.9),
  level10(10, 'Grandmaster', 1.0);

  final int level;
  final String displayName;
  final double strength; // 0.0 to 1.0 - affects move quality

  const AiLevel(this.level, this.displayName, this.strength);
}
