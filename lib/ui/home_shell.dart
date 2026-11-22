import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import 'expiring_screen.dart';
import 'planning_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'shopping_screen.dart';
import 'stock_screen.dart';

/// Écran principal : barre de navigation (en bas sur petit écran, à gauche
/// sur iPad) et les 6 onglets de l'appli.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Permet à un écran de changer d'onglet (ex. bandeau « bientôt périmés »).
  static void goTo(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?.select(index);

  static const stock = 0, expiring = 1, recipes = 2, planning = 3, shopping = 4, settings = 5;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final expiring = state.expiringBatches.length;
    final toBuy = state.shopping.values.where((i) => !i.checked).length;

    Widget badge(IconData icon, int n) =>
        n == 0 ? Icon(icon) : Badge(label: Text('$n'), child: Icon(icon));

    final items = [
      (const Icon(Icons.kitchen_outlined), const Icon(Icons.kitchen), 'Stock'),
      (badge(Icons.timer_outlined, expiring), badge(Icons.timer, expiring), 'Bientôt périmés'),
      (const Icon(Icons.menu_book_outlined), const Icon(Icons.menu_book), 'Recettes'),
      (const Icon(Icons.calendar_month_outlined), const Icon(Icons.calendar_month), 'Planning'),
      (badge(Icons.shopping_cart_outlined, toBuy), badge(Icons.shopping_cart, toBuy), 'Courses'),
      (const Icon(Icons.settings_outlined), const Icon(Icons.settings), 'Réglages'),
    ];

    final pages = const [
      StockScreen(),
      ExpiringScreen(),
      RecipesScreen(),
      PlanningScreen(),
      ShoppingScreen(),
      SettingsScreen(),
    ];
    final body = IndexedStack(index: _index, children: pages);

    final wide = MediaQuery.sizeOf(context).width >= 700;
    // Pas de Scaffold ici : chaque onglet a le sien, pour que les messages
    // en bas d'écran fassent remonter ses boutons au lieu de les cacher.
    if (wide) {
      return Material(
        child: Row(children: [
          SafeArea(
            child: NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, sel, label) in items)
                  NavigationRailDestination(icon: icon, selectedIcon: sel, label: Text(label)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Material(
      child: Column(children: [
        Expanded(child: body),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            for (final (icon, sel, label) in items)
              NavigationDestination(icon: icon, selectedIcon: sel, label: label),
          ],
        ),
      ]),
    );
  }
}
