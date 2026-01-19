enum StoneColor {
  black,
  white;

  /// Get the opponent's color
  StoneColor get opponent {
    return this == StoneColor.black ? StoneColor.white : StoneColor.black;
  }

  /// Display name
  String get displayName {
    return this == StoneColor.black ? 'Black' : 'White';
  }
}
