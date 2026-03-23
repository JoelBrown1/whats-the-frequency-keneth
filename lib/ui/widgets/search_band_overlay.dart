// lib/ui/widgets/search_band_overlay.dart
// Shaded overlay widget for the ResonanceSearchBand on the frequency chart.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

double _log10(double x) => log(x) / ln10;

class SearchBandOverlay extends StatelessWidget {
  final ResonanceSearchBand band;
  final double chartMinHz;
  final double chartMaxHz;

  const SearchBandOverlay({
    super.key,
    required this.band,
    this.chartMinHz = 100.0,
    this.chartMaxHz = 20000.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logMin = _log10(chartMinHz);
        final logMax = _log10(chartMaxHz);
        final logLow = _log10(band.lowHz.clamp(chartMinHz, chartMaxHz));
        final logHigh = _log10(band.highHz.clamp(chartMinHz, chartMaxHz));

        final leftFraction = (logLow - logMin) / (logMax - logMin);
        final rightFraction = (logHigh - logMin) / (logMax - logMin);

        final left = leftFraction * constraints.maxWidth;
        final width =
            (rightFraction - leftFraction) * constraints.maxWidth;

        return Stack(
          children: [
            Positioned(
              left: left,
              width: width,
              top: 0,
              bottom: 0,
              child: Container(
                color: Colors.teal.withValues(alpha: 0.12),
              ),
            ),
          ],
        );
      },
    );
  }
}
