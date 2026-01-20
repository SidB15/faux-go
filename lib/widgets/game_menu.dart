import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'confirm_dialog.dart';

/// Shows the game menu as a modal bottom sheet
Future<void> showGameMenu(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.cardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _GameMenuContent(ref: ref),
  );
}

class _GameMenuContent extends StatelessWidget {
  final WidgetRef ref;

  const _GameMenuContent({required this.ref});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Game Menu',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),

            // Menu items
            _MenuItem(
              icon: Icons.play_arrow,
              label: 'Resume',
              onTap: () => Navigator.of(context).pop(),
            ),

            _MenuItem(
              icon: Icons.refresh,
              label: 'Restart Game',
              onTap: () => _handleRestart(context),
            ),

            _MenuItem(
              icon: Icons.add,
              label: 'New Game',
              onTap: () => _handleNewGame(context),
            ),

            _MenuItem(
              icon: Icons.home,
              label: 'Main Menu',
              onTap: () => _handleMainMenu(context),
            ),

            const Divider(height: 24),

            _MenuItem(
              icon: Icons.help_outline,
              label: 'How to Play',
              onTap: () => _handleHowToPlay(context),
            ),

            _MenuItem(
              icon: Icons.exit_to_app,
              label: 'Quit App',
              color: Colors.red.shade600,
              onTap: () => _handleQuitApp(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRestart(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restart Game?',
      message: 'Current progress will be lost.',
      confirmText: 'Restart',
      isDangerous: true,
    );

    if (confirmed && context.mounted) {
      final settings = ref.read(gameSettingsProvider);
      ref.read(gameStateProvider.notifier).startGame(settings);
      Navigator.of(context).pop(); // Close menu
    }
  }

  Future<void> _handleNewGame(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Start New Game?',
      message: 'Current progress will be lost.',
      confirmText: 'New Game',
      isDangerous: true,
    );

    if (confirmed && context.mounted) {
      ref.read(gameStateProvider.notifier).resetGame();
      Navigator.of(context).pop(); // Close menu
      context.go('/setup');
    }
  }

  Future<void> _handleMainMenu(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Return to Main Menu?',
      message: 'Current progress will be lost.',
      confirmText: 'Main Menu',
      isDangerous: true,
    );

    if (confirmed && context.mounted) {
      ref.read(gameStateProvider.notifier).resetGame();
      Navigator.of(context).pop(); // Close menu
      context.go('/');
    }
  }

  Future<void> _handleHowToPlay(BuildContext context) async {
    Navigator.of(context).pop(); // Close menu first
    await showRulesDialog(context);
  }

  Future<void> _handleQuitApp(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Quit App?',
      message: 'Are you sure you want to exit?',
      confirmText: 'Quit',
      isDangerous: true,
    );

    if (confirmed) {
      SystemNavigator.pop();
    }
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? AppTheme.primaryColor;

    return ListTile(
      leading: Icon(icon, color: itemColor),
      title: Text(
        label,
        style: TextStyle(
          color: itemColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
