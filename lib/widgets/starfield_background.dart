import 'dart:math';
import 'package:flutter/material.dart';

/// A star in the background
class _Star {
  final double x;
  final double y;
  final double size;
  final double opacity;
  final Color color;

  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.color,
  });
}

/// Generates and caches stars for consistent rendering
class _StarfieldGenerator {
  static List<_Star>? _cachedStars;
  static Size? _cachedSize;

  static List<_Star> generateStars(Size size, {int starCount = 150}) {
    // Return cached stars if size hasn't changed significantly
    if (_cachedStars != null && _cachedSize != null) {
      if ((_cachedSize!.width - size.width).abs() < 50 &&
          (_cachedSize!.height - size.height).abs() < 50) {
        return _cachedStars!;
      }
    }

    final random = Random(42); // Fixed seed for consistent stars
    final stars = <_Star>[];

    // Star colors - mostly white with some blue/purple tints
    final starColors = [
      Colors.white,
      Colors.white,
      Colors.white,
      const Color(0xFFE0E8FF), // Slight blue
      const Color(0xFFFFE8E0), // Slight orange
      const Color(0xFFE8E0FF), // Slight purple
    ];

    for (int i = 0; i < starCount; i++) {
      // Distribute stars across a larger area than the visible region
      final x = random.nextDouble() * size.width * 1.5 - size.width * 0.25;
      final y = random.nextDouble() * size.height * 1.5 - size.height * 0.25;

      // Vary star sizes - most are small, few are larger
      final sizeRoll = random.nextDouble();
      double starSize;
      if (sizeRoll < 0.7) {
        starSize = 0.5 + random.nextDouble() * 0.5; // Tiny stars
      } else if (sizeRoll < 0.9) {
        starSize = 1.0 + random.nextDouble() * 1.0; // Small stars
      } else {
        starSize = 1.5 + random.nextDouble() * 1.5; // Brighter stars
      }

      // Vary opacity
      final opacity = 0.3 + random.nextDouble() * 0.7;

      stars.add(_Star(
        x: x,
        y: y,
        size: starSize,
        opacity: opacity,
        color: starColors[random.nextInt(starColors.length)],
      ));
    }

    _cachedStars = stars;
    _cachedSize = size;
    return stars;
  }
}

/// Paints a starfield background
class StarfieldPainter extends CustomPainter {
  final Offset offset;
  final double parallaxFactor;

  StarfieldPainter({
    this.offset = Offset.zero,
    this.parallaxFactor = 0.1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw dark background gradient
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.2,
      colors: [
        const Color(0xFF1a1a2e), // Dark blue center
        const Color(0xFF0f0f1a), // Darker edges
      ],
    );
    canvas.drawRect(bgRect, Paint()..shader = bgGradient.createShader(bgRect));

    // Optional: Add subtle nebula effect
    _drawNebula(canvas, size);

    // Draw stars with parallax
    final stars = _StarfieldGenerator.generateStars(size);
    for (final star in stars) {
      final parallaxOffset = Offset(
        offset.dx * parallaxFactor * (star.size / 2),
        offset.dy * parallaxFactor * (star.size / 2),
      );

      final starPaint = Paint()
        ..color = star.color.withValues(alpha: star.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(star.x + parallaxOffset.dx, star.y + parallaxOffset.dy),
        star.size,
        starPaint,
      );

      // Add glow to larger stars
      if (star.size > 1.5) {
        final glowPaint = Paint()
          ..color = star.color.withValues(alpha: star.opacity * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(
          Offset(star.x + parallaxOffset.dx, star.y + parallaxOffset.dy),
          star.size * 2,
          glowPaint,
        );
      }
    }
  }

  void _drawNebula(Canvas canvas, Size size) {
    // Subtle colored nebula patches
    final random = Random(123);
    final nebulaColors = [
      const Color(0xFF4a0080).withValues(alpha: 0.05), // Purple
      const Color(0xFF000080).withValues(alpha: 0.05), // Blue
      const Color(0xFF800040).withValues(alpha: 0.03), // Magenta
    ];

    for (int i = 0; i < 3; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 100 + random.nextDouble() * 200;

      final nebulaPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            nebulaColors[i % nebulaColors.length],
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));

      canvas.drawCircle(Offset(x, y), radius, nebulaPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return offset != oldDelegate.offset;
  }
}

/// Widget that displays the starfield background
class StarfieldBackground extends StatelessWidget {
  final Widget child;
  final Offset parallaxOffset;

  const StarfieldBackground({
    super.key,
    required this.child,
    this.parallaxOffset = Offset.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background fills entire space
        Positioned.fill(
          child: CustomPaint(
            painter: StarfieldPainter(offset: parallaxOffset),
          ),
        ),
        // Child on top
        child,
      ],
    );
  }
}
