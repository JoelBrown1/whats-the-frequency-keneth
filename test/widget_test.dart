// Basic smoke test — verifies the app can build without crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/mock_audio_engine_platform.dart';
import 'package:whats_the_frequency/main.dart';

void main() {
  setUpAll(() {
    AudioEnginePlatformInterface.instance = MockAudioEnginePlatform();
  });

  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WtfkApp()));
    // Just verify the widget tree builds.
    expect(find.byType(WtfkApp), findsOneWidget);
  });
}
