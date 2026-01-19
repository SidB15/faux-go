import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

class GameOverScreen extends ConsumerWidget {
  const GameOverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No game data'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    }

    final winner = gameState.winner;
    final isTie = winner == null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'GAME OVER',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 32),

                // Winner card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (!isTie) ...[
                        // Winner stone
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: winner == StoneColor.black
                                ? AppTheme.blackStone
                                : AppTheme.whiteStone,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: winner == StoneColor.black
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.grey.shade300,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(2, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${winner.displayName.toUpperCase()} WINS!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.handshake,
                          size: 64,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "IT'S A TIE!",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Score display
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildScoreColumn(
                            color: StoneColor.black,
                            captures: gameState.blackCaptures,
                            isWinner: winner == StoneColor.black,
                          ),
                          Container(
                            height: 60,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            color: Colors.grey.shade300,
                          ),
                          _buildScoreColumn(
                            color: StoneColor.white,
                            captures: gameState.whiteCaptures,
                            isWinner: winner == StoneColor.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Move count
                Text(
                  'Total moves: ${gameState.moveCount}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 48),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        ref.read(gameStateProvider.notifier).resetGame();
                        context.go('/');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Main Menu'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        // Increment game count for ad tracking
                        ref.read(gameCountProvider.notifier).state++;

                        // Show interstitial ad every 3 games
                        final gameCount = ref.read(gameCountProvider);
                        if (gameCount % 3 == 0) {
                          await AdService().showInterstitialAd();
                        }

                        // Restart with same settings
                        final settings = ref.read(gameSettingsProvider);
                        ref.read(gameStateProvider.notifier).startGame(settings);
                        if (context.mounted) {
                          context.go('/game');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Play Again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreColumn({
    required StoneColor color,
    required int captures,
    required bool isWinner,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color == StoneColor.black
                ? AppTheme.blackStone
                : AppTheme.whiteStone,
            shape: BoxShape.circle,
            border: Border.all(
              color: color == StoneColor.black
                  ? Colors.white.withOpacity(0.2)
                  : Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$captures',
          style: TextStyle(
            fontSize: 28,
            fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
            color: isWinner ? AppTheme.accentColor : AppTheme.primaryColor,
          ),
        ),
        Text(
          'captures',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
