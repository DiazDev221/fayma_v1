import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/router/app_router.dart';
import 'package:fayma/screens/add_client_screen.dart';
import 'package:fayma/screens/client_detail_screen.dart';
import 'package:fayma/screens/clients_screen.dart';
import 'package:fayma/screens/edit_client_screen.dart';
import 'package:fayma/screens/home_screen.dart';
import 'package:fayma/screens/settings_screen.dart';
import 'package:fayma/services/shop_settings.dart';
import 'package:fayma/theme/app_theme.dart';

class _FakeShopSettings implements ShopSettingsStore {
  @override
  Future<String> readShopName() async => 'Boutique test';

  @override
  Future<void> saveShopName(String name) async {}
}

Widget _app(
  InMemoryCreditRepository repository, {
  String initialLocation = AppRoutes.clients,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.clients,
        builder: (context, state) => const ClientsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.newClient,
        builder: (context, state) => const AddClientScreen(),
      ),
      GoRoute(
        path: '/clients/:id/edit',
        builder: (context, state) =>
            EditClientScreen(clientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/clients/:id',
        builder: (context, state) =>
            ClientDetailScreen(clientId: state.pathParameters['id']!),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      creditRepositoryProvider.overrideWithValue(repository),
      shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('la page clients liste et recherche les clients', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(InMemoryCreditRepository.withDemoData()));
    await tester.pumpAndSettle();

    expect(find.text('Tous les clients'), findsOneWidget);
    expect(find.text('Moussa Diop'), findsOneWidget);
    expect(find.text('Fatou Ndiaye'), findsOneWidget);
    expect(find.text('Aissatou Ba'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Fatou');
    await tester.pump();

    expect(find.text('Fatou Ndiaye'), findsOneWidget);
    expect(find.text('Moussa Diop'), findsNothing);

    await tester.enterText(find.byType(TextField), '7788');
    await tester.pump();

    expect(find.text('Aissatou Ba'), findsOneWidget);
    expect(find.text('Fatou Ndiaye'), findsNothing);
  });

  testWidgets('l’accueil ouvre la page clients', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        InMemoryCreditRepository.withDemoData(),
        initialLocation: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total à recevoir'), findsOneWidget);

    await tester.tap(find.byTooltip('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Paramètres'), findsOneWidget);

    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();

    expect(find.text('Tous les clients'), findsOneWidget);
  });

  testWidgets('modifier un client met à jour ses coordonnées', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = InMemoryCreditRepository.withDemoData();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modifier Moussa Diop'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier le client'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    expect(find.text('Diop'), findsOneWidget);

    await tester.enterText(fields.at(0), 'Fall');
    await tester.enterText(fields.at(1), 'Mamadou');
    await tester.enterText(fields.at(2), '76 000 11 22');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer les modifications'),
    );
    await tester.pumpAndSettle();

    final updated = await repository.getClient('c1');
    expect(updated?.nom, 'Fall');
    expect(updated?.prenom, 'Mamadou');
    expect(updated?.telephone, '76 000 11 22');
    expect(find.text('Tous les clients'), findsOneWidget);
    expect(find.text('Mamadou Fall'), findsOneWidget);
  });

  testWidgets('les champs obligatoires et le format du numéro sont validés',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = InMemoryCreditRepository.withDemoData();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modifier Moussa Diop'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '');
    await tester.enterText(fields.at(2), '77 12 34');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer les modifications'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nom obligatoire'), findsOneWidget);
    expect(
      find.text('Numéro à 9 chiffres (ex : 77 123 45 67)'),
      findsOneWidget,
    );
    expect((await repository.getClient('c1'))?.nom, 'Diop');
  });

  testWidgets('le numéro d’un autre client est refusé, le sien est accepté',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = InMemoryCreditRepository.withDemoData();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modifier Fatou Ndiaye'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '77 123 45 67');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer les modifications'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ce numéro existe déjà (Moussa Diop)'), findsOneWidget);
    expect(find.text('Modifier le client'), findsOneWidget);
    expect((await repository.getClient('c2'))?.telephone, '78 654 32 10');

    // Le numéro actuel du client en cours de modification reste autorisé.
    await tester.enterText(fields.at(1), 'Fatoumata');
    await tester.enterText(fields.at(2), '78 654 32 10');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer les modifications'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tous les clients'), findsOneWidget);
    final updated = await repository.getClient('c2');
    expect(updated?.prenom, 'Fatoumata');
    expect(updated?.telephone, '78 654 32 10');
  });
}
