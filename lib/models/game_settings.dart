import 'game_enums.dart';

class GameSettings {
  final GameMode mode;
  final int targetValue;

  const GameSettings({
    required this.mode,
    required this.targetValue,
  });

  /// Default settings
  static const GameSettings defaultSettings = GameSettings(
    mode: GameMode.fixedMoves,
    targetValue: 200,
  );

  GameSettings copyWith({
    GameMode? mode,
    int? targetValue,
  }) {
    return GameSettings(
      mode: mode ?? this.mode,
      targetValue: targetValue ?? this.targetValue,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameSettings &&
        other.mode == mode &&
        other.targetValue == targetValue;
  }

  @override
  int get hashCode => mode.hashCode ^ targetValue.hashCode;
}
