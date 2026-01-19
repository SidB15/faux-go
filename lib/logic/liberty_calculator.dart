import '../models/models.dart';

class LibertyCalculator {
  final Board board;

  LibertyCalculator(this.board);

  /// Get liberties for a single stone at position
  /// Liberties are empty adjacent intersections
  Set<Position> getLibertiesForStone(Position pos) {
    final liberties = <Position>{};
    final stone = board.getStoneAt(pos);

    if (stone == null) return liberties;

    for (final adjacent in pos.adjacentPositions) {
      if (board.isValidPosition(adjacent) && board.isEmpty(adjacent)) {
        liberties.add(adjacent);
      }
    }

    return liberties;
  }

  /// Find all stones connected to the stone at position (same color)
  /// Uses flood-fill algorithm
  Set<Position> findGroup(Position startPos) {
    final stone = board.getStoneAt(startPos);
    if (stone == null) return {};

    final group = <Position>{};
    final toVisit = <Position>[startPos];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (group.contains(current)) continue;

      final currentStone = board.getStoneAt(current);
      if (currentStone != stone) continue;

      group.add(current);

      for (final adjacent in current.adjacentPositions) {
        if (board.isValidPosition(adjacent) &&
            !group.contains(adjacent) &&
            board.getStoneAt(adjacent) == stone) {
          toVisit.add(adjacent);
        }
      }
    }

    return group;
  }

  /// Get total liberties for a group of connected stones
  Set<Position> getGroupLiberties(Set<Position> group) {
    final liberties = <Position>{};

    for (final pos in group) {
      for (final adjacent in pos.adjacentPositions) {
        if (board.isValidPosition(adjacent) && board.isEmpty(adjacent)) {
          liberties.add(adjacent);
        }
      }
    }

    return liberties;
  }

  /// Get liberties for the group containing the stone at position
  Set<Position> getLibertiesForGroup(Position pos) {
    final group = findGroup(pos);
    return getGroupLiberties(group);
  }

  /// Check if a group has any liberties
  bool groupHasLiberties(Position pos) {
    return getLibertiesForGroup(pos).isNotEmpty;
  }
}
