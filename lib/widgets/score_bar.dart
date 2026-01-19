import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class ScoreBar extends StatelessWidget {
  final GameState gameState;
  final bool isAiThinking;

  const ScoreBar({
    super.key,
    required this.gameState,
    this.isAiThinking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Black score
          _buildScoreItem(
            color: StoneColor.black,
            captures: gameState.blackCaptures,
            isCurrentPlayer: gameState.currentPlayer == StoneColor.black,
          ),

          // Progress indicator
          Text(
            gameState.progressText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),

          // White score
          _buildScoreItem(
            color: StoneColor.white,
            captures: gameState.whiteCaptures,
            isCurrentPlayer: gameState.currentPlayer == StoneColor.white,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreItem({
    required StoneColor color,
    required int captures,
    required bool isCurrentPlayer,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrentPlayer ? Colors.white.withOpacity(0.2) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color == StoneColor.black
                  ? AppTheme.blackStone
                  : AppTheme.whiteStone,
              shape: BoxShape.circle,
              border: Border.all(
                color: color == StoneColor.black
                    ? Colors.white.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.5),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$captures',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: isCurrentPlayer ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
