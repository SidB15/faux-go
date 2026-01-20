import 'board.dart';
import 'enclosure.dart';
import 'game_enums.dart';
import 'game_settings.dart';
import 'position.dart';
import 'stone.dart';

class GameState {
  final GameSettings settings;
  final Board board;
  final StoneColor currentPlayer;
  final int moveCount;
  final int blackCaptures;
  final int whiteCaptures;
  final Position? lastMove;
  final GameStatus status;
  final StoneColor? winner;
  final List<Board> history;
  final int consecutivePasses;
  final List<Enclosure> enclosures;

  const GameState({
    required this.settings,
    required this.board,
    required this.currentPlayer,
    this.moveCount = 0,
    this.blackCaptures = 0,
    this.whiteCaptures = 0,
    this.lastMove,
    this.status = GameStatus.setup,
    this.winner,
    this.history = const [],
    this.consecutivePasses = 0,
    this.enclosures = const [],
  });

  /// Create initial game state
  factory GameState.initial(GameSettings settings) {
    return GameState(
      settings: settings,
      board: Board(),
      currentPlayer: StoneColor.black,
      status: GameStatus.playing,
    );
  }

  /// Get captures for a specific player
  int getCapturesFor(StoneColor color) {
    return color == StoneColor.black ? blackCaptures : whiteCaptures;
  }

  /// Check if undo is available
  bool get canUndo => history.isNotEmpty;

  /// Get progress text based on game mode
  String get progressText {
    switch (settings.mode) {
      case GameMode.fixedMoves:
        return 'Move ${moveCount + 1}/${settings.targetValue}';
      case GameMode.captureTarget:
        return 'First to ${settings.targetValue}';
    }
  }

  /// Check if a position is inside any opponent's enclosure
  bool isInsideOpponentEnclosure(Position pos, StoneColor player) {
    for (final enclosure in enclosures) {
      if (enclosure.owner != player && enclosure.containsPosition(pos)) {
        return true;
      }
    }
    return false;
  }

  /// Get all enclosures owned by a specific player
  List<Enclosure> getEnclosuresFor(StoneColor color) {
    return enclosures.where((e) => e.owner == color).toList();
  }

  GameState copyWith({
    GameSettings? settings,
    Board? board,
    StoneColor? currentPlayer,
    int? moveCount,
    int? blackCaptures,
    int? whiteCaptures,
    Position? lastMove,
    bool clearLastMove = false,
    GameStatus? status,
    StoneColor? winner,
    bool clearWinner = false,
    List<Board>? history,
    int? consecutivePasses,
    List<Enclosure>? enclosures,
  }) {
    return GameState(
      settings: settings ?? this.settings,
      board: board ?? this.board,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      moveCount: moveCount ?? this.moveCount,
      blackCaptures: blackCaptures ?? this.blackCaptures,
      whiteCaptures: whiteCaptures ?? this.whiteCaptures,
      lastMove: clearLastMove ? null : (lastMove ?? this.lastMove),
      status: status ?? this.status,
      winner: clearWinner ? null : (winner ?? this.winner),
      history: history ?? this.history,
      consecutivePasses: consecutivePasses ?? this.consecutivePasses,
      enclosures: enclosures ?? this.enclosures,
    );
  }
}
