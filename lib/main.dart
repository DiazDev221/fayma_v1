import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/sqlite_credit_repository.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barres d'état et de navigation visibles sur mobile.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Application utilisée en mode portrait uniquement.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Dates en français (ex : "12 oct. 2026").
  await initializeDateFormatting('fr_FR');

  // Base de données dans le dossier privé de l'application.
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final repository = SqliteCreditRepository.open(p.join(dir.path, 'fayma.db'));

  runApp(
    ProviderScope(
      overrides: [creditRepositoryProvider.overrideWithValue(repository)],
      child: const FaymaApp(),
    ),
  );
}

class FaymaApp extends StatelessWidget {
  const FaymaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fayma',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
