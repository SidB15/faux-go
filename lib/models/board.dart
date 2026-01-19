import 'position.dart';
import 'stone.dart';

class Board {
  static const int defaultSize = 48;

  final int size;
  final Map<Position, StoneColor> _stones;

  Board({
    this.size = defaultSize,
    Map<Position, StoneColor>? stones,
  }) : _stones = stones ?? {};

  /// Get all stones on the board
  Map<Position, StoneColor> get stones => Map.unmodifiable(_stones);

  /// Get stone at position (null if empty)
  StoneColor? getStoneAt(Position pos) {
    return _stones[pos];
  }

  /// Check if position is empty
  bool isEmpty(Position pos) {
    return !_stones.containsKey(pos);
  }

  /// Check if position is within board bounds
  bool isValidPosition(Position pos) {
    return pos.isValidFor(size);
  }

  /// Create a new board with a stone placed
  Board placeStone(Position pos, StoneColor color) {
    if (!isValidPosition(pos)) {
      throw ArgumentError('Position $pos is outside board bounds');
    }
    if (!isEmpty(pos)) {
      throw ArgumentError('Position $pos is already occupied');
    }

    final newStones = Map<Position, StoneColor>.from(_stones);
    newStones[pos] = color;
    return Board(size: size, stones: newStones);
  }

  /// Create a new board with stones removed
  Board removeStones(Set<Position> positions) {
    final newStones = Map<Position, StoneColor>.from(_stones);
    for (final pos in positions) {
      newStones.remove(pos);
    }
    return Board(size: size, stones: newStones);
  }

  /// Get all positions of a specific color
  Set<Position> getPositionsOfColor(StoneColor color) {
    return _stones.entries
        .where((e) => e.value == color)
        .map((e) => e.key)
        .toSet();
  }

  /// Create a copy of this board
  Board copy() {
    return Board(size: size, stones: Map.from(_stones));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Board) return false;
    if (other.size != size) return false;
    if (other._stones.length != _stones.length) return false;
    for (final entry in _stones.entries) {
      if (other._stones[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(size, Object.hashAll(_stones.entries));
}
