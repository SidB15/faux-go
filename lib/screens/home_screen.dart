import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/banner_ad_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Main content
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo / Title
                    const Text(
                      'SIMPLY GO',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                        letterSpacing: 4,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Stone icons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStone(AppTheme.blackStone),
                        const SizedBox(width: 12),
                        _buildStone(AppTheme.whiteStone),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Tagline
                    Text(
                      'Encircle. Capture. Win.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // New Game button
                    ElevatedButton(
                      onPressed: () => context.go('/setup'),
                      child: const Text('NEW GAME'),
                    ),
                  ],
                ),
              ),
            ),

            // Banner ad
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildStone(Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: color == AppTheme.blackStone
              ? Colors.white.withOpacity(0.2)
              : Colors.grey.shade300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
    );
  }
}
