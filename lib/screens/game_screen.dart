import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../logic/logic.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final AiEngine _aiEngine = AiEngine();
  bool _isAiThinking = false;

  @override
  void initState() {
    super.initState();
    // Schedule AI move check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPlayAiMove();
    });
  }

  void _checkAndPlayAiMove() {
    final gameState = ref.read(gameStateProvider);
    final settings = ref.read(gameSettingsProvider);

    if (gameState == null ||
        gameState.status != GameStatus.playing ||
        !settings.isVsCpu ||
        _isAiThinking) {
      return;
    }

    // AI plays as white (second player)
    if (gameState.currentPlayer == StoneColor.white) {
      _playAiMove(gameState, settings);
    }
  }

  Future<void> _playAiMove(GameState gameState, GameSettings settings) async {
    setState(() {
      _isAiThinking = true;
    });

    // Add a small delay so the AI move feels more natural
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final move = _aiEngine.calculateMove(
      gameState.board,
      StoneColor.white,
      settings.aiLevel,
    );

    if (move != null) {
      ref.read(gameStateProvider.notifier).placeStone(move);
    } else {
      // AI passes if no valid move
      ref.read(gameStateProvider.notifier).pass();
    }

    if (mounted) {
      setState(() {
        _isAiThinking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);
    final settings = ref.watch(gameSettingsProvider);

    // Listen for state changes to trigger AI moves
    ref.listen<GameState?>(gameStateProvider, (previous, next) {
      if (next != null &&
          next.status == GameStatus.playing &&
          settings.isVsCpu &&
          next.currentPlayer == StoneColor.white &&
          !_isAiThinking) {
        // Delay to let the UI update first
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _checkAndPlayAiMove();
        });
      }
    });

    // Navigate to game over when finished
    if (gameState?.status == GameStatus.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/gameover');
      });
    }

    if (gameState == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Faux Go')),
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
            ScoreBar(
              gameState: gameState,
              isAiThinking: _isAiThinking,
            ),

            // Game board (expandable)
            Expanded(
              child: Stack(
                children: [
                  // Main board
                  GameBoard(
                    enabled: !_isAiThinking &&
                        !(settings.isVsCpu &&
                            gameState.currentPlayer == StoneColor.white),
                  ),

                  // Mini map in bottom right
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: MiniMap(board: gameState.board),
                  ),

                  // AI thinking indicator
                  if (_isAiThinking)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'AI thinking...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Game controls
            GameControls(
              enabled: !_isAiThinking,
            ),

            // Banner ad
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}
