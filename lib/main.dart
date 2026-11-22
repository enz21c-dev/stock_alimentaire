import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/app_state.dart';
import 'platform/platform.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  AppState? state;
  Object? error;
  try {
    state = await AppState.open();
    requestPersistentStorage();
  } catch (e) {
    error = e;
  }
  runApp(StockAlimentaireApp(state: state, error: error));
}

class StockAlimentaireApp extends StatelessWidget {
  const StockAlimentaireApp({super.key, this.state, this.error});
  final AppState? state;
  final Object? error;

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32), brightness: b),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Stock Alimentaire',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: state == null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "Impossible d'ouvrir la base de données de l'appli.\n"
                    "Vérifie que Safari n'est pas en navigation privée.\n\n$error",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : const HomeShell(),
    );
    return state == null ? app : AppScope(state: state!, child: app);
  }
}
