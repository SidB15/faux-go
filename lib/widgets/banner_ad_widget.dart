import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause/resume ad to prevent ImageReader buffer issues
    if (state == AppLifecycleState.paused) {
      _isPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      _isPaused = false;
      // Reload ad if it was disposed
      if (_bannerAd == null && mounted) {
        _loadAd();
      }
    }
  }

  void _loadAd() {
    if (_isPaused) return;

    _bannerAd = AdService().createBannerAd(
      onAdLoaded: (ad) {
        if (mounted && !_isPaused) {
          setState(() {
            _isAdLoaded = true;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        debugPrint('Banner ad failed to load: $error');
        ad.dispose();
      },
    );
    _bannerAd!.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdLoaded || _bannerAd == null) {
      // Placeholder while ad loads
      return Container(
        height: 50,
        color: Colors.grey.shade200,
        child: const Center(
          child: Text(
            'Ad',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return SizedBox(
      height: _bannerAd!.size.height.toDouble(),
      width: _bannerAd!.size.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
