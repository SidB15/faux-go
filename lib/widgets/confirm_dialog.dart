import 'package:flutter/material.dart';

/// Shows a confirmation dialog with title, message, and confirm/cancel buttons
/// Returns true if confirmed, false if cancelled
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDangerous
              ? ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows rules/how to play dialog
Future<void> showRulesDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How to Play'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Objective',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Completely encircle your opponent\'s stones to capture them. '
              'The player with the most captures wins!',
            ),
            SizedBox(height: 16),
            Text(
              'Rules',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('• Black plays first, then players alternate'),
            Text('• Tap an intersection to place a stone'),
            Text('• Surround opponent stones to capture them'),
            Text('• Captured stones are removed from the board'),
            Text('• Encirclements create forts (shown with lines)'),
            Text('• Opponents cannot place stones inside your forts'),
            Text('• Pass if you have no good moves'),
            SizedBox(height: 16),
            Text(
              'Game Modes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('• Fixed Moves: Game ends after set number of moves'),
            Text('• Capture Target: First to capture X stones wins'),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it!'),
        ),
      ],
    ),
  );
}
