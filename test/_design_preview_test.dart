import 'dart:io';

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
import 'package:fayma/screens/purchase_screen.dart';
import 'package:fayma/screens/repayment_screen.dart';
import 'package:fayma/screens/settings_screen.dart';
import 'package:fayma/services/backup/backup_settings.dart';
import 'package:fayma/theme/app_theme.dart';

class _FakeBackupSettings implements BackupSettingsStore {
  @override
  Future<String> deviceId() async => 'appareil-test';

  @override
  Future<String> shopId() async => 'boutique-test';

  @override
  Future<void> setShopId(String shopId) async {}

  @override
  Future<DateTime?> lastBackupAt() async => DateTime(2026, 10, 21);

  @override
  Future<void> setLastBackupAt(DateTime date) async {}
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      creditRepositoryProvider.overrideWithValue(
        InMemoryCreditRepository.withDemoData(),
      ),
      backupSettingsProvider.overrideWithValue(_FakeBackupSettings()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
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
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr_FR');
    final loader = FontLoader('Manrope');
    for (final name in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Manrope-$name.ttf'));
    }
    await loader.load();
  });

  testWidgets('preview screens', (tester) async {
    // Par défaut, ce test vérifie simplement que chaque écran se met en page
    // sans exception. Les captures sont écrites uniquement sur demande :
    //   FAYMA_PREVIEW=1 flutter test test/_design_preview_test.dart \
    //     --update-goldens
    final capture = Platform.environment['FAYMA_PREVIEW'] == '1';

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> shot(Widget screen, String name) async {
      await tester.pumpWidget(_wrap(screen));
      await tester.pumpAndSettle();
      if (!capture) return;
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('/tmp/opencode/fayma_preview/$name.png'),
      );
    }

    await shot(const HomeScreen(), '01_home');
    await shot(const ClientDetailScreen(clientId: 'c1'), '02_client');
    await shot(const ClientsScreen(), '02b_clients');
    await shot(const EditClientScreen(clientId: 'c1'), '02c_edit_client');
    await shot(const AddClientScreen(), '03_add_client');
    await shot(const PurchaseScreen(clientId: 'c1'), '04_purchase');
    await shot(const RepaymentScreen(clientId: 'c1'), '05_repayment');
    await shot(const DepositScreen(clientId: 'c1'), '06_deposit');
    await shot(const BackupScreen(), '07_backup');
    await shot(const SettingsScreen(), '08_settings');
    if (Platform.isLinux) {
      // Keep the test deterministic on CI too.
    }
  });
}
