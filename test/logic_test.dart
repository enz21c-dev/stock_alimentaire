import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:stock_alimentaire/data/app_state.dart';
import 'package:stock_alimentaire/logic/stock_logic.dart';
import 'package:stock_alimentaire/logic/units.dart';
import 'package:stock_alimentaire/models/models.dart';
import 'package:stock_alimentaire/services/open_food_facts.dart';

void main() {
  final today = DateTime(2026, 11, 22);

  group('Jours restants et couleur', () {
    test('calcul des jours', () {
      expect(daysUntil(DateTime(2026, 11, 22), today: today), 0);
      expect(daysUntil(DateTime(2026, 11, 25), today: today), 3);
      expect(daysUntil(DateTime(2026, 11, 21), today: today), -1);
      // L'heure ne compte pas
      expect(daysUntil(DateTime(2026, 11, 23), today: DateTime(2026, 11, 22, 23, 59)), 1);
      // Passage à l'heure d'été (29 mars 2026) sans décalage
      expect(daysUntil(DateTime(2026, 3, 30), today: DateTime(2026, 3, 28)), 2);
    });

    test('vert / orange / rouge', () {
      expect(expiryStatus(4), ExpiryStatus.ok);
      expect(expiryStatus(3), ExpiryStatus.soon);
      expect(expiryStatus(0), ExpiryStatus.soon);
      expect(expiryStatus(-1), ExpiryStatus.expired);
      expect(expiryStatus(5, alertDays: 5), ExpiryStatus.soon);
    });
  });

  group('Consommation FEFO', () {
    final lotTard = Batch(id: 'b', productId: 'p', quantity: 2, expirationDate: DateTime(2026, 12, 7));
    final lotTot = Batch(id: 'a', productId: 'p', quantity: 2, expirationDate: DateTime(2026, 12, 2));

    test('prend d\'abord le lot qui périme le plus tôt', () {
      final r = consumeFefo([lotTard, lotTot], 1);
      expect(r.newQuantities, {'a': 1});
      expect(r.missing, 0);
    });

    test('déborde sur le lot suivant', () {
      final r = consumeFefo([lotTard, lotTot], 3);
      expect(r.newQuantities, {'a': 0, 'b': 1});
    });

    test('signale ce qui manque', () {
      final r = consumeFefo([lotTard, lotTot], 5.5);
      expect(r.newQuantities, {'a': 0, 'b': 0});
      expect(r.missing, 1.5);
    });
  });

  group('Unités', () {
    test('conversions', () {
      expect(convert(500, 'g', 'kg'), 0.5);
      expect(convert(1.5, 'L', 'ml'), 1500);
      expect(convert(1, 'pièce', 'g'), isNull);
      expect(humanize(1500, 'g'), (1.5, 'kg'));
      expect(formatQty(1.5, 'kg'), '1,5 kg');
      expect(formatQty(2, 'pièce'), '2 pièces');
      expect(parseNumber('0,25'), 0.25);
    });

    test('noms normalisés', () {
      expect(normalizeName('Œufs'), 'oeuf');
      expect(normalizeName('  Pâtes  complètes '), 'pate complete');
    });

    test('quantité Open Food Facts', () {
      expect(parseOffQuantity('500 g'), (500.0, 'g'));
      expect(parseOffQuantity('4 x 125 g'), (500.0, 'g'));
      expect(parseOffQuantity('1,5 L'), (1.5, 'L'));
      expect(parseOffQuantity('33 cl'), (330.0, 'ml'));
      expect(parseOffQuantity('6 pots'), isNull);
    });

    test('catégories Open Food Facts', () {
      expect(mapOffCategory(['en:frozen-foods', 'en:pizzas']), 'Surgelé');
      expect(mapOffCategory(['en:dairies', 'en:yogurts']), 'Frais');
      expect(mapOffCategory(['en:spreads', 'en:sweet-spreads']), 'Épicerie');
      expect(mapOffCategory([]), 'Autre');
    });
  });

  group('Besoins des recettes et liste de courses', () {
    final oeufs = Product(id: 'oeufs', name: 'Oeufs frais', unit: 'pièce');
    final farine = Product(id: 'farine', name: 'Farine T55', unit: 'kg');
    final lait = Product(id: 'lait', name: 'Lait demi-écrémé', unit: 'L');
    final products = [oeufs, farine, lait];
    final batches = [
      Batch(productId: 'oeufs', quantity: 4, expirationDate: DateTime(2026, 12, 1)),
      Batch(productId: 'oeufs', quantity: 6, expirationDate: DateTime(2026, 11, 1)), // périmés : ignorés
      Batch(productId: 'farine', quantity: 1, expirationDate: DateTime(2027, 6, 1)),
      Batch(productId: 'lait', quantity: 0.5, expirationDate: DateTime(2026, 11, 30)),
    ];
    final crepes = Recipe(id: 'crepes', name: 'Crêpes', ingredients: [
      RecipeIngredient(name: 'Oeufs frais', quantity: 3, productId: 'oeufs'),
      RecipeIngredient(name: 'farine', quantity: 250, unit: 'g'), // relié par le nom
      RecipeIngredient(name: 'Lait', quantity: 500, unit: 'ml'),
    ]);
    final gateau = Recipe(id: 'gateau', name: 'Gâteau', ingredients: [
      RecipeIngredient(name: 'Oeufs frais', quantity: 3, productId: 'oeufs'),
      RecipeIngredient(name: 'Sucre', quantity: 100, unit: 'g'),
    ]);
    final recipes = {crepes.id: crepes, gateau.id: gateau};

    List<Need> needs(List<MealPlanEntry> plan) =>
        computeNeeds(plan: plan, recipes: recipes, products: products, batches: batches, today: today);

    test('cumule les recettes et compare au stock', () {
      final n = needs([MealPlanEntry(recipeId: 'crepes'), MealPlanEntry(recipeId: 'gateau')]);
      final byName = {for (final x in n) x.name: x};
      expect(byName['Oeufs frais']!.needed, 6);
      expect(byName['Oeufs frais']!.available, 4); // les 6 périmés ne comptent pas
      expect(byName['Oeufs frais']!.missing, 2);
      expect(byName['Farine T55']!.needed, 250);
      expect(byName['Farine T55']!.isMissing, isFalse);
      expect(byName['Lait demi-écrémé']!.isMissing, isFalse);
      expect(byName['Sucre']!.missing, 100);
      // Les manquants sont en premier
      expect(n.take(2).every((x) => x.isMissing), isTrue);
    });

    test('ignore les recettes déjà faites', () {
      final n = needs([MealPlanEntry(recipeId: 'gateau', done: true)]);
      expect(n, isEmpty);
    });

    test('génère la liste de courses en gardant le manuel et le coché', () {
      final n = needs([MealPlanEntry(recipeId: 'crepes'), MealPlanEntry(recipeId: 'gateau')]);
      final manuel = ShoppingItem(name: 'Pain');
      final ancienAuto = ShoppingItem(name: 'Beurre', auto: true);
      final coche = ShoppingItem(name: 'Sucre', auto: true, checked: true);
      final list = regenerateShopping([manuel, ancienAuto, coche], n);
      final names = list.map((i) => i.name).toList();
      expect(names, contains('Pain'));
      expect(names, isNot(contains('Beurre'))); // plus nécessaire
      expect(names.where((x) => x == 'Sucre').length, 1); // déjà coché, pas de doublon
      final oeufsItem = list.firstWhere((i) => i.name == 'Oeufs frais');
      expect(oeufsItem.quantity, 2);
      expect(oeufsItem.auto, isTrue);
    });
  });

  group('Base de données', () {
    late AppState state;
    var n = 0;
    setUp(() async {
      state = await AppState.open(factory: databaseFactoryMemory, name: 'test${n++}.db');
    });

    test('pas de doublon de produit : nouveau lot sur le même produit', () async {
      await state.addStock(name: 'Yaourt nature', category: 'Frais', unit: 'pièce', quantity: 2,
          expiration: today.add(const Duration(days: 10)));
      await state.addStock(name: 'yaourt  NATURE', category: 'Frais', unit: 'pièce', quantity: 2,
          expiration: today.add(const Duration(days: 15)));
      expect(state.products.length, 1);
      final p = state.products.values.first;
      expect(state.batchesOf(p.id).length, 2);
      expect(state.totalOf(p.id), 4);
    });

    test('même code-barres = même produit, conversion d\'unité', () async {
      await state.addStock(name: 'Farine', barcode: '123', category: 'Épicerie', unit: 'kg', quantity: 1,
          expiration: today);
      await state.addStock(name: 'Farine bio', barcode: '123', category: 'Épicerie', unit: 'g', quantity: 500,
          expiration: today);
      expect(state.products.length, 1);
      expect(state.totalOf(state.products.keys.first), 1.5);
    });

    test('consommer puis annuler', () async {
      await state.addStock(name: 'Yaourt', category: 'Frais', unit: 'pièce', quantity: 2,
          expiration: today.add(const Duration(days: 15)));
      await state.addStock(name: 'Yaourt', category: 'Frais', unit: 'pièce', quantity: 2,
          expiration: today.add(const Duration(days: 10)));
      final id = state.products.keys.first;
      final snap = await state.consume(id, 3);
      final lots = state.batchesOf(id);
      expect(lots.length, 1);
      expect(lots.first.quantity, 1);
      expect(daysUntil(lots.first.expirationDate, today: today), 15);
      await state.undo(snap);
      expect(state.totalOf(id), 4);
      expect(state.batchesOf(id).length, 2);
    });

    test('export puis import restaurent tout', () async {
      await state.addStock(name: 'Riz', category: 'Épicerie', unit: 'kg', quantity: 2, expiration: today);
      await state.saveRecipe(Recipe(name: 'Riz cantonais', ingredients: [
        RecipeIngredient(name: 'Riz', quantity: 300, unit: 'g'),
      ]));
      state.settings.alertDays = 5;
      await state.saveSettings();
      final json = state.exportJson();

      final other = await AppState.open(factory: databaseFactoryMemory, name: 'autre${n++}.db');
      await other.importJson(json);
      expect(other.products.values.single.name, 'Riz');
      expect(other.recipes.values.single.ingredients.single.quantity, 300);
      expect(other.settings.alertDays, 5);
      await expectLater(other.importJson('{"a":1}'), throwsFormatException);
      expect(other.products.length, 1); // fichier invalide : rien n'est effacé
    });

    test('recette faite : décrément du stock', () async {
      await state.addStock(name: 'Oeufs', category: 'Frais', unit: 'pièce', quantity: 6,
          expiration: today.add(const Duration(days: 10)));
      final r = Recipe(name: 'Omelette', ingredients: [RecipeIngredient(name: 'oeufs', quantity: 3)]);
      final snap = await state.consumeRecipe(r);
      expect(state.totalOf(state.products.keys.first), 3);
      await state.undo(snap);
      expect(state.totalOf(state.products.keys.first), 6);
    });

    test('liste de courses mise à jour automatiquement', () async {
      final r = Recipe(name: 'Omelette', ingredients: [RecipeIngredient(name: 'Oeufs', quantity: 3)]);
      await state.saveRecipe(r);
      await state.savePlanEntry(MealPlanEntry(recipeId: r.id));
      expect(state.shopping.values.single.name, 'Oeufs');
      await state.addStock(name: 'Oeufs', category: 'Frais', unit: 'pièce', quantity: 6,
          expiration: DateTime.now().add(const Duration(days: 10)));
      expect(state.shopping, isEmpty);
    });
  });
}
