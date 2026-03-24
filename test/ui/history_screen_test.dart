// test/ui/history_screen_test.dart
// Verifies HistoryScreen lazy-loading behaviour:
//   - loadSummaries() is called at init; list items render from summaries.
//   - loadFull() is NOT called during list render (lazy load contract).
//   - loadFull() IS called only when a summary is tapped in selectionMode.
//   - By-pickup grouping groups measurements under ExpansionTile headers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/data/measurement_repository.dart';
import 'package:whats_the_frequency/data/models/measurement.dart';
import 'package:whats_the_frequency/data/models/measurement_summary.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/measurement_provider.dart';
import 'package:whats_the_frequency/ui/screens/history_screen.dart';

// ─── Mock ─────────────────────────────────────────────────────────────────────

class _MockRepository extends Mock implements MeasurementRepository {}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

MeasurementSummary _summary({
  String id = 'id-1',
  String pickupLabel = 'PAF neck',
  String? pickupId = 'pickup-001',
  double hz = 4000.0,
  double q = 3.0,
}) =>
    MeasurementSummary(
      id: id,
      timestamp: DateTime(2026, 3, 24),
      pickupLabel: pickupLabel,
      pickupId: pickupId,
      resonanceFrequencyHz: hz,
      qFactor: q,
    );

Measurement _fullMeasurement(String id) => Measurement(
      schemaVersion: 1,
      id: id,
      timestamp: DateTime(2026, 3, 24),
      pickupLabel: 'PAF neck',
      pickupId: 'pickup-001',
      sweepConfig: const SweepConfig(),
      resonanceSearchBand: const ResonanceSearchBand(),
      magnitudeDB: List.generate(361, (i) => i.toDouble()),
      resonanceFrequencyHz: 4000.0,
      qFactor: 3.0,
      hardware: MeasurementHardware(
        interfaceDeviceName: 'Scarlett 2i2 USB',
        interfaceUID: 'uid-123',
        calibrationId: 'cal-456',
        calibrationTimestamp: DateTime(2026, 3, 24),
        appVersion: '1.0.0',
      ),
    );

// ─── Widget wrapper ────────────────────────────────────────────────────────────

Widget _wrap(_MockRepository repo, {bool selectionMode = false}) {
  return ProviderScope(
    overrides: [
      measurementRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HistoryScreen(selectionMode: selectionMode),
    ),
  );
}

// ─── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
  });

  testWidgets('list renders from summaries — loadFull never called',
      (tester) async {
    when(() => repo.loadSummaries()).thenAnswer((_) async => [
          _summary(pickupLabel: 'PAF neck', hz: 4000.0, q: 3.0),
        ]);
    // loadFull must never be called during render; fail immediately if it is.
    when(() => repo.loadFull(any())).thenThrow(StateError(
        'loadFull called during list render — lazy loading contract violated'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('PAF neck'), findsOneWidget);
    verifyNever(() => repo.loadFull(any()));
  });

  testWidgets('empty state shown when there are no summaries', (tester) async {
    when(() => repo.loadSummaries()).thenAnswer((_) async => []);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // No list tiles — something indicating empty state should appear.
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('multiple summaries all appear in flat list', (tester) async {
    when(() => repo.loadSummaries()).thenAnswer((_) async => [
          _summary(id: 'a', pickupLabel: 'PAF neck'),
          _summary(id: 'b', pickupLabel: 'Strat bridge'),
          _summary(id: 'c', pickupLabel: 'Telecaster neck'),
        ]);
    when(() => repo.loadFull(any())).thenThrow(
        StateError('loadFull should not be called during flat list render'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('PAF neck'), findsOneWidget);
    expect(find.text('Strat bridge'), findsOneWidget);
    expect(find.text('Telecaster neck'), findsOneWidget);
    verifyNever(() => repo.loadFull(any()));
  });

  testWidgets('grouped view groups by pickupId under ExpansionTile',
      (tester) async {
    when(() => repo.loadSummaries()).thenAnswer((_) async => [
          _summary(id: 'a', pickupLabel: 'PAF neck', pickupId: 'p1', hz: 4000),
          _summary(id: 'b', pickupLabel: 'PAF neck', pickupId: 'p1', hz: 4100),
          _summary(id: 'c', pickupLabel: 'Strat bridge', pickupId: 'p2', hz: 6500),
        ]);
    when(() => repo.loadFull(any())).thenThrow(
        StateError('loadFull should not be called in grouped view'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // Toggle to grouped view.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // Two pickup groups should exist as ExpansionTiles.
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    verifyNever(() => repo.loadFull(any()));
  });

  testWidgets('loadFull called only on tap in selectionMode', (tester) async {
    when(() => repo.loadSummaries()).thenAnswer((_) async => [
          _summary(id: 'tap-me', pickupLabel: 'Neck pickup'),
        ]);
    when(() => repo.loadFull('tap-me')).thenAnswer(
        (_) async => _fullMeasurement('tap-me'));

    FrequencyResponse? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [measurementRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => ElevatedButton(
              child: const Text('Open'),
              onPressed: () async {
                popped = await Navigator.of(ctx).push<FrequencyResponse>(
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(selectionMode: true),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Open the HistoryScreen via push so pop() can return a value.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // loadFull must not have been called yet — just rendering the list.
    verifyNever(() => repo.loadFull(any()));

    // Tap the summary item.
    await tester.tap(find.text('Neck pickup'));
    await tester.pumpAndSettle();

    // Now loadFull should have been called exactly once.
    verify(() => repo.loadFull('tap-me')).called(1);
    expect(popped, isNotNull);
    expect(popped!.primaryPeak.frequencyHz, equals(4000.0));
  });
}
