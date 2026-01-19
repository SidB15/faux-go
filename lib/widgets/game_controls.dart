import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class GameControls extends ConsumerWidget {
  final bool enabled;

  const GameControls({
    super.key,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState == null || gameState.status != GameStatus.playing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Undo button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled && gameState.canUndo
                  ? () => ref.read(gameStateProvider.notifier).undo()
                  : null,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(
                  color: gameState.canUndo
                      ? AppTheme.primaryColor
                      : Colors.grey.shade300,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Turn indicator
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: gameState.currentPlayer == StoneColor.black
                          ? AppTheme.blackStone
                          : AppTheme.whiteStone,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: gameState.currentPlayer == StoneColor.black
                            ? Colors.white.withOpacity(0.3)
                            : Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${gameState.currentPlayer.displayName}'s Turn",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Pass button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled
                  ? () => ref.read(gameStateProvider.notifier).pass()
                  : null,
              icon: const Icon(Icons.skip_next),
              label: const Text('Pass'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: const BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
