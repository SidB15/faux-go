import 'game_enums.dart';

class GameSettings {
  final GameMode mode;
  final int targetValue;
  final OpponentType opponentType;
  final AiLevel aiLevel;

  const GameSettings({
    required this.mode,
    required this.targetValue,
    this.opponentType = OpponentType.human,
    this.aiLevel = AiLevel.level5,
  });

  /// Default settings
  static const GameSettings defaultSettings = GameSettings(
    mode: GameMode.fixedMoves,
    targetValue: 200,
    opponentType: OpponentType.human,
    aiLevel: AiLevel.level5,
  );

  /// Check if playing against CPU
  bool get isVsCpu => opponentType == OpponentType.cpu;

  GameSettings copyWith({
    GameMode? mode,
    int? targetValue,
    OpponentType? opponentType,
    AiLevel? aiLevel,
  }) {
    return GameSettings(
      mode: mode ?? this.mode,
      targetValue: targetValue ?? this.targetValue,
      opponentType: opponentType ?? this.opponentType,
      aiLevel: aiLevel ?? this.aiLevel,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameSettings &&
        other.mode == mode &&
        other.targetValue == targetValue &&
        other.opponentType == opponentType &&
        other.aiLevel == aiLevel;
  }

  @override
  int get hashCode =>
      mode.hashCode ^
      targetValue.hashCode ^
      opponentType.hashCode ^
      aiLevel.hashCode;
}
