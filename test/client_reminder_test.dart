import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/main.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/router/app_router.dart';
import 'package:fayma/services/shop_settings.dart';
import 'package:fayma/services/sms_sender.dart';

class _FakeSmsSender implements SmsSender {
  String? phone;
  String? message;
  int calls = 0;

  @override
  Future<SmsResult> send({
    required String phone,
    required String message,
  }) async {
    this.phone = phone;
    this.message = message;
    calls++;
    return const SmsResult(SmsStatus.opened);
  }
}

class _FakeShopSettings implements ShopSettingsStore {
  @override
  Future<String> readShopName() async => 'Boutique Awa';

  @override
  Future<void> saveShopName(String name) async {}
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  setUp(() {
    // Le routeur est un singleton : chaque test repart de l'accueil.
    appRouter.go(AppRoutes.home);
  });

  testWidgets('un rappel prépare le SMS depuis la fiche client',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sender = _FakeSmsSender();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
          smsSenderProvider.overrideWithValue(sender),
          shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
        ],
        child: const FaymaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Moussa Diop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moussa Diop'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Envoyer un rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer un rappel'));
    await tester.pumpAndSettle();

    expect(sender.calls, 1);
    expect(sender.phone, '77 123 45 67');
    expect(sender.message, contains('il vous reste 25 000 FCFA à payer'));
    expect(sender.message, contains('Dette la plus ancienne : 1 oct. 2026'));
    expect(sender.message, endsWith('Boutique Awa'));
  });

  testWidgets('la cloche de l’accueil prépare le rappel du bon client',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sender = _FakeSmsSender();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
          smsSenderProvider.overrideWithValue(sender),
          shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
        ],
        child: const FaymaApp(),
      ),
    );
    await tester.pumpAndSettle();

    final bell = find.byTooltip('Envoyer un rappel').first;
    await tester.tap(bell);
    await tester.pumpAndSettle();

    expect(sender.calls, 1);
    // Les clients sont triés par nom : Fatou Ndiaye est la première endettée.
    expect(sender.phone, '78 654 32 10');
    expect(sender.message, contains('il vous reste 8 500 FCFA à payer'));
  });
}
