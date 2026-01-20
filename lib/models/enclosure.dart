import 'position.dart';
import 'stone.dart';

/// Represents an enclosure (fort) on the board
/// An enclosure is formed when a player completely surrounds opponent stones
/// The wall positions form the boundary that opponents cannot pass through
class Enclosure {
  /// The player who owns this enclosure
  final StoneColor owner;

  /// Positions of stones forming the enclosure wall
  final Set<Position> wallPositions;

  /// Positions inside the enclosure (that were captured)
  final Set<Position> interiorPositions;

  const Enclosure({
    required this.owner,
    required this.wallPositions,
    required this.interiorPositions,
  });

  /// Check if a position is inside this enclosure
  bool containsPosition(Position pos) {
    return interiorPositions.contains(pos);
  }

  /// Check if a position is part of the wall
  bool isWallPosition(Position pos) {
    return wallPositions.contains(pos);
  }

  /// Get all 8 neighboring positions (orthogonal + diagonal)
  static List<Position> _getAllNeighbors(Position pos) {
    return [
      Position(pos.x - 1, pos.y),     // left
      Position(pos.x + 1, pos.y),     // right
      Position(pos.x, pos.y - 1),     // up
      Position(pos.x, pos.y + 1),     // down
      Position(pos.x - 1, pos.y - 1), // top-left
      Position(pos.x + 1, pos.y - 1), // top-right
      Position(pos.x - 1, pos.y + 1), // bottom-left
      Position(pos.x + 1, pos.y + 1), // bottom-right
    ];
  }

  /// Get pairs of adjacent wall positions for drawing lines
  /// Includes both orthogonal (horizontal/vertical) and diagonal connections
  /// Returns list of position pairs that should be connected
  List<(Position, Position)> get wallEdges {
    final edges = <(Position, Position)>[];

    for (final pos in wallPositions) {
      for (final neighbor in _getAllNeighbors(pos)) {
        if (wallPositions.contains(neighbor)) {
          // Avoid duplicates by only adding if pos < neighbor (lexicographically)
          if (pos.x < neighbor.x || (pos.x == neighbor.x && pos.y < neighbor.y)) {
            edges.add((pos, neighbor));
          }
        }
      }
    }

    return edges;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Enclosure) return false;
    return owner == other.owner &&
        wallPositions.length == other.wallPositions.length &&
        wallPositions.containsAll(other.wallPositions);
  }

  @override
  int get hashCode => Object.hash(owner, wallPositions.length);
}
