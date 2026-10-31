import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/main.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/utils/format.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('L\'accueil affiche les clients de démo', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
        ],
        child: const FaymaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fayma'), findsOneWidget);
    expect(find.text('Total à recevoir'), findsOneWidget);
    expect(find.text('Dépôts disponibles'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('home-total-deposits'))).data,
      formatFcfa(12000),
    );
    expect(find.text('Moussa Diop'), findsOneWidget);
    expect(find.text('Fatou Ndiaye'), findsOneWidget);
    expect(find.text('Aissatou Ba'), findsOneWidget);
  });

  testWidgets('Seul l\'en-tête reste fixe pendant le défilement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
        ],
        child: const FaymaApp(),
      ),
    );
    await tester.pumpAndSettle();

    final headerBefore = tester.getTopLeft(find.text('Fayma'));
    final settingsBefore = tester.getTopLeft(find.byTooltip('Paramètres'));
    final totalBefore = tester.getTopLeft(find.text('Total à recevoir'));
    final reportBefore = tester.getTopLeft(find.text('Rapport général PDF'));

    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Fayma')), headerBefore);
    expect(tester.getTopLeft(find.byTooltip('Paramètres')), settingsBefore);
    expect(
      tester.getTopLeft(find.text('Total à recevoir')).dy,
      lessThan(totalBefore.dy),
    );
    expect(
      tester.getTopLeft(find.text('Rapport général PDF')).dy,
      lessThan(reportBefore.dy),
    );
  });

  testWidgets('L\'écran de sauvegarde s\'ouvre depuis les paramètres',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
        ],
        child: const FaymaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Paramètres'), findsOneWidget);

    await tester.tap(find.text('Sauvegarde'));
    await tester.pumpAndSettle();

    expect(find.text('Sauvegarde'), findsOneWidget);
    expect(find.text('Code de récupération'), findsNothing);
    await tester.drag(
      find.byKey(const Key('backup-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer la sauvegarde'), findsOneWidget);
    expect(find.text('Partager la sauvegarde'), findsOneWidget);
    expect(find.text('Restaurer une sauvegarde'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
