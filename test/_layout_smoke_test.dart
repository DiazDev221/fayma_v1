import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fayma/data/in_memory_credit_repository.dart';
import 'package:fayma/providers.dart';
import 'package:fayma/screens/add_client_screen.dart';
import 'package:fayma/screens/backup_screen.dart';
import 'package:fayma/screens/client_detail_screen.dart';
import 'package:fayma/screens/clients_screen.dart';
import 'package:fayma/screens/deposit_screen.dart';
import 'package:fayma/screens/edit_client_screen.dart';
import 'package:fayma/screens/home_screen.dart';
import 'package:fayma/screens/pick_contact_screen.dart';
import 'package:fayma/screens/purchase_screen.dart';
import 'package:fayma/screens/repayment_screen.dart';
import 'package:fayma/screens/settings_screen.dart';
import 'package:fayma/services/backup/backup_settings.dart';
import 'package:fayma/services/shop_settings.dart';
import 'package:fayma/theme/app_theme.dart';

class _FakeBackupSettings implements BackupSettingsStore {
  @override
  Future<String> deviceId() async => 'appareil-test';
  @override
  Future<String> shopId() async => 'boutique-test';
  @override
  Future<void> setShopId(String shopId) async {}
  @override
  Future<DateTime?> lastBackupAt() async => null;
  @override
  Future<void> setLastBackupAt(DateTime at) async {}
}

class _FakeShopSettings implements ShopSettingsStore {
  @override
  Future<String> readShopName() async => 'Boutique test';

  @override
  Future<void> saveShopName(String name) async {}
}

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        creditRepositoryProvider.overrideWithValue(
          InMemoryCreditRepository.withDemoData(),
        ),
        backupSettingsProvider.overrideWithValue(_FakeBackupSettings()),
        shopSettingsProvider.overrideWithValue(_FakeShopSettings()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr_FR');
  });

  // Le plugin contacts n'existe pas dans les tests : on simule un refus pour
  // que l'écran quitte son état de chargement et que la mise en page soit
  // testable.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('github.com/QuisApp/flutter_contacts'),
      (call) async {
        if (call.method == 'requestPermission') return false;
        return <dynamic>[];
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('github.com/QuisApp/flutter_contacts'),
      null,
    );
  });

  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'clients': const ClientsScreen(),
    'client': const ClientDetailScreen(clientId: 'c1'),
    'edit-client': const EditClientScreen(clientId: 'c1'),
    'add': const AddClientScreen(),
    'purchase': const PurchaseScreen(clientId: 'c1'),
    'repayment': const RepaymentScreen(clientId: 'c1'),
    'deposit': const DepositScreen(clientId: 'c1'),
    'backup': const BackupScreen(),
    'contacts': const PickContactScreen(),
    'settings': const SettingsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('layout ${entry.key} 320', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(entry.value));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: entry.key);
    });
  }
}
