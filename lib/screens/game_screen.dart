import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);

    // Navigate to game over when finished
    if (gameState?.status == GameStatus.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/gameover');
      });
    }

    if (gameState == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Simply GO')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No game in progress'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/setup'),
                child: const Text('Start New Game'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Score bar at top
            ScoreBar(gameState: gameState),

            // Game board (expandable)
            Expanded(
              child: Stack(
                children: [
                  // Main board
                  const GameBoard(),

                  // Mini map in bottom right
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: MiniMap(board: gameState.board),
                  ),
                ],
              ),
            ),

            // Game controls
            const GameControls(),

            // Banner ad
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}
