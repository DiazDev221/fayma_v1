import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/screens/client_detail_screen.dart';
import 'package:fayma/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('l’historique affiche l’opération la plus récente en premier',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ClientDetailScreen(clientId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final newest = tester.getTopLeft(find.text('12 oct. 2026')).dy;
    final middle =
        tester.getTopLeft(find.text('8 oct. 2026 · Orange Money')).dy;
    final oldest = tester.getTopLeft(find.text('1 oct. 2026')).dy;

    expect(newest, lessThan(middle));
    expect(middle, lessThan(oldest));
  });
}
