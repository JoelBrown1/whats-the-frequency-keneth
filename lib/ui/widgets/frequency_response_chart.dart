// lib/ui/widgets/frequency_response_chart.dart
// Log-axis frequency response chart using fl_chart.
// X-axis: pre-transformed to log10(frequencyHz).
// Touch: custom GestureDetector bypasses fl_chart touch system.
//        Inverse log transform used to report cursor frequency in Hz.
// Accessibility: Semantics wrapper with resonance/Q description.

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:whats_the_frequency/constants.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/ui/widgets/search_band_overlay.dart';

const double _minFreq = kChartMinFreqHz;
const double _maxFreq = kChartMaxFreqHz;

const Color _kPrimaryColor = Colors.tealAccent;
const Color _kOverlayColor = Colors.orangeAccent;

double _log10(double x) => log(x) / ln10;

/// Convert a chart x-coordinate back to Hz using the inverse log transform.
double chartXToFrequency(double chartX, double chartWidth) {
  final logMin = _log10(_minFreq);
  final logMax = _log10(_maxFreq);
  final logF = logMin + (chartX / chartWidth) * (logMax - logMin);
  return pow(10.0, logF).toDouble();
}

class FrequencyResponseChart extends StatefulWidget {
  final FrequencyResponse? frequencyResponse;
  final FrequencyResponse? overlayResponse;
  final String? primaryLabel;
  final String? overlayLabel;
  final ResonanceSearchBand? searchBand;

  const FrequencyResponseChart({
    super.key,
    this.frequencyResponse,
    this.overlayResponse,
    this.primaryLabel,
    this.overlayLabel,
    this.searchBand,
  });

  @override
  State<FrequencyResponseChart> createState() => _FrequencyResponseChartState();
}

class _FrequencyResponseChartState extends State<FrequencyResponseChart> {
  double? _cursorHz;
  double? _cursorDb;
  double? _cursorOverlayDb; // nullable: absent until overlay is loaded

  double _nearestDb(FrequencyResponse response, double hz) {
    double nearestDb = 0;
    double nearestDist = double.infinity;
    for (int i = 0; i < response.frequencyHz.length; i++) {
      final dist = (response.frequencyHz[i] - hz).abs();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestDb = response.magnitudeDb[i];
      }
    }
    return nearestDb;
  }

  void _handleTapDown(TapDownDetails details, BoxConstraints constraints) {
    final hz = chartXToFrequency(
        details.localPosition.dx, constraints.maxWidth);
    final response = widget.frequencyResponse;
    if (response == null) return;
    setState(() {
      _cursorHz = hz;
      _cursorDb = _nearestDb(response, hz);
      _cursorOverlayDb = widget.overlayResponse != null
          ? _nearestDb(widget.overlayResponse!, hz)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final response = widget.frequencyResponse;

    final semanticsLabel = response != null
        ? 'Frequency response chart. '
            'Resonance frequency: ${response.primaryPeak.frequencyHz.toStringAsFixed(0)} Hz. '
            'Q-factor: ${response.primaryPeak.qFactor.toStringAsFixed(1)}.'
        : 'Frequency response chart. No data available.';

    return Semantics(
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (d) => _handleTapDown(d, constraints),
            child: Stack(
              children: [
                _buildChart(response),
                if (response != null && widget.overlayResponse != null)
                  _buildLegend(
                    primaryLabel: widget.primaryLabel ?? 'Current',
                    overlayLabel: widget.overlayLabel ?? 'Overlay',
                  ),
                if (_cursorHz != null && _cursorDb != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_cursorHz!.toStringAsFixed(0)} Hz  '
                            '${_cursorDb!.toStringAsFixed(1)} dB',
                            style: const TextStyle(
                                color: _kPrimaryColor, fontSize: 12),
                          ),
                          if (_cursorOverlayDb != null)
                            Text(
                              '${widget.overlayLabel ?? 'Overlay'}: '
                              '${_cursorOverlayDb!.toStringAsFixed(1)} dB',
                              style: const TextStyle(
                                  color: _kOverlayColor, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _buildLegend({
    required String primaryLabel,
    required String overlayLabel,
  }) {
    return Positioned(
      top: 8,
      left: 48,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _legendEntry(color: _kPrimaryColor, dashed: false, label: primaryLabel),
            _legendEntry(color: _kOverlayColor, dashed: true, label: overlayLabel),
          ],
        ),
      ),
    );
  }

  static Widget _legendEntry({
    required Color color,
    required bool dashed,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 12,
            child: CustomPaint(
              painter: _LineSwatch(color: color, dashed: dashed),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildChart(FrequencyResponse? response) {
    if (response == null) {
      return const Center(child: Text('No data — complete a measurement'));
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < response.frequencyHz.length; i++) {
      final f = response.frequencyHz[i];
      if (f >= _minFreq && f <= _maxFreq) {
        spots.add(FlSpot(_log10(f), response.magnitudeDb[i]));
      }
    }

    final overlaySpots = <FlSpot>[];
    final overlay = widget.overlayResponse;
    if (overlay != null) {
      for (int i = 0; i < overlay.frequencyHz.length; i++) {
        final f = overlay.frequencyHz[i];
        if (f >= _minFreq && f <= _maxFreq) {
          overlaySpots.add(FlSpot(_log10(f), overlay.magnitudeDb[i]));
        }
      }
    }

    final chart = LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            dotData: const FlDotData(show: false),
            color: _kPrimaryColor,
            barWidth: 1.5,
          ),
          if (overlaySpots.isNotEmpty)
            LineChartBarData(
              spots: overlaySpots,
              isCurved: false,
              dotData: const FlDotData(show: false),
              color: _kOverlayColor,
              barWidth: 1.5,
              dashArray: [4, 4],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) =>
                  Text('${value.toStringAsFixed(0)} dB',
                      style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final hz = pow(10.0, value).toDouble();
                String label;
                if (hz >= 10000) {
                  label = '${(hz / 1000).toStringAsFixed(0)}k';
                } else if (hz >= 1000) {
                  label = '${(hz / 1000).toStringAsFixed(0)}k';
                } else {
                  label = hz.toStringAsFixed(0);
                }
                return Text(label, style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );

    final band = widget.searchBand;
    if (band == null) return chart;

    return Stack(
      children: [
        SearchBandOverlay(
          band: band,
          chartMinHz: _minFreq,
          chartMaxHz: _maxFreq,
        ),
        chart,
      ],
    );
  }
}

class _LineSwatch extends CustomPainter {
  final Color color;
  final bool dashed;

  const _LineSwatch({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    if (dashed) {
      const dashWidth = 4.0;
      const gapWidth = 4.0;
      double x = 0;
      while (x < size.width) {
        final end = (x + dashWidth).clamp(0.0, size.width);
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
        x += dashWidth + gapWidth;
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LineSwatch old) =>
      old.color != color || old.dashed != dashed;
}
