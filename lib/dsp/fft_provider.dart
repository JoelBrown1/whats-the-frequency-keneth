// lib/dsp/fft_provider.dart
// FFT abstraction layer — swap fftea for Accelerate without changing callers.

import 'dart:typed_data';
import 'package:fftea/fftea.dart';

/// Abstract FFT provider.
/// Swap implementations by changing the registered instance.
abstract class FftProvider {
  /// Forward FFT: real samples in, interleaved [real, imag] Float64List out.
  Float64List forward(Float64List samples);

  /// Inverse FFT: interleaved [real, imag] Float64List in, real samples out.
  Float64List inverse(Float64List spectrum);
}

/// Default implementation using the fftea package (pure Dart).
class FfteaFftProvider implements FftProvider {
  @override
  Float64List forward(Float64List samples) {
    final fft = FFT(samples.length);
    final freq = fft.realFft(samples);
    // Convert Float64x2List to interleaved Float64List.
    final result = Float64List(freq.length * 2);
    for (int i = 0; i < freq.length; i++) {
      result[i * 2] = freq[i].x;
      result[i * 2 + 1] = freq[i].y;
    }
    return result;
  }

  @override
  Float64List inverse(Float64List spectrum) {
    final n = spectrum.length ~/ 2;
    final fft = FFT(n * 2 - 2); // assumes discardConjugates format
    final complexList = Float64x2List(n);
    for (int i = 0; i < n; i++) {
      complexList[i] = Float64x2(spectrum[i * 2], spectrum[i * 2 + 1]);
    }
    return fft.realInverseFft(complexList);
  }
}
