// Basic smoke test — verifies the app can build without crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/audio/mock_audio_engine_platform.dart';
import 'package:whats_the_frequency/main.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEnginePlatformProvider.overrideWithValue(
              MockAudioEnginePlatform()),
        ],
        child: const WtfkApp(),
      ),
    );
    expect(find.byType(WtfkApp), findsOneWidget);
  });
}
