import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/screens/settings_screen.dart';
import 'package:fayma/services/shop_settings.dart';
import 'package:fayma/theme/app_theme.dart';

class _FakeShopSettings implements ShopSettingsStore {
  _FakeShopSettings(this.name);

  String name;
  String? savedName;

  @override
  Future<String> readShopName() async => name;

  @override
  Future<void> saveShopName(String value) async {
    savedName = value;
    name = value;
  }
}

void main() {
  testWidgets('les paramètres regroupent clients, boutique et sauvegarde',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final shopSettings = _FakeShopSettings('Boutique test');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditRepositoryProvider.overrideWithValue(
            InMemoryCreditRepository.withDemoData(),
          ),
          shopSettingsProvider.overrideWithValue(shopSettings),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Sauvegarde'), findsOneWidget);
    expect(find.text('3 clients enregistrés.'), findsOneWidget);
    expect(find.text('Nom de la boutique'), findsOneWidget);

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'Boutique test');

    await tester.enterText(find.byType(TextFormField), 'Boutique Awa');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer le nom'),
    );
    await tester.pumpAndSettle();

    expect(shopSettings.savedName, 'Boutique Awa');
    expect(find.text('Nom de la boutique enregistré.'), findsOneWidget);
  });
}
