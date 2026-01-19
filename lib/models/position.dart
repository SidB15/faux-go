class Position {
  final int x;
  final int y;

  const Position(this.x, this.y);

  /// Get adjacent positions (up, down, left, right)
  List<Position> get adjacentPositions {
    return [
      Position(x - 1, y),
      Position(x + 1, y),
      Position(x, y - 1),
      Position(x, y + 1),
    ];
  }

  /// Check if position is within board bounds
  bool isValidFor(int boardSize) {
    return x >= 0 && x < boardSize && y >= 0 && y < boardSize;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Position && other.x == x && other.y == y;
  }

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  @override
  String toString() => 'Position($x, $y)';
}
