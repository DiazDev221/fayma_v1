import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/screens/purchase_screen.dart';
import 'package:fayma/theme/app_theme.dart';

void main() {
  testWidgets('un achat très élevé reste enregistrable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
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
          home: const PurchaseScreen(clientId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Riz en gros');
    await tester.enterText(find.byType(TextField).at(1), '1000000');
    await tester.tap(find.byTooltip('Ajouter le produit'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enregistrer l’achat'),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('le défilement ne fait pas perdre le focus de la saisie',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 640));
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
          home: const PurchaseScreen(clientId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final productField = find.byType(TextField).first;
    await tester.enterText(productField, 'Riz en gros');
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: productField, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.manual,
    );

    // Un glissement sur la liste ne doit ni fermer le clavier ni retirer le
    // focus du champ en cours de saisie.
    await tester.drag(find.text('Ajouter un produit'), const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(editable.focusNode.hasFocus, isTrue);
  });
}
