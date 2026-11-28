import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:stock_alimentaire/data/app_state.dart';
import 'package:stock_alimentaire/logic/stock_logic.dart';
import 'package:stock_alimentaire/models/models.dart';
import 'package:stock_alimentaire/services/local_products.dart';
import 'package:stock_alimentaire/services/open_food_facts.dart';

void main() {
  final today = DateTime(2026, 11, 22);

  test('catégories : « …-foods-and-beverages » ne veut pas dire Boissons', () {
    expect(mapOffCategory(['en:plant-based-foods-and-beverages', 'en:plant-based-foods', 'en:pastas']), 'Épicerie');
    expect(mapOffCategory(['en:plant-based-foods-and-beverages', 'en:fruit-based-foods-and-beverages', 'en:jams']),
        'Épicerie');
    expect(mapOffCategory(['en:plant-based-foods-and-beverages', 'en:beverages', 'en:plant-milks']), 'Boissons');
    expect(mapOffCategory(['en:charcuteries', 'en:hams']), 'Frais');
  });

  test('quantité proposée au scan', () {
    final p = parsePack('4 x 125 g')!;
    expect((p.count, p.each, p.unit), (4, 125.0, 'g'));
    expect(suggestQuantity(p), (4.0, 'pièce'));
    expect(suggestQuantity(parsePack('400 g')), (400.0, 'g'));
    expect(suggestQuantity(parsePack('1,5 L')), (1.5, 'L'));
    expect(suggestQuantity(null), (1.0, 'pièce'));
  });

  test('calories : produits et recettes, par personne', () {
    final nutella = Product(id: 'n', name: 'Nutella', unit: 'g', kcal100: 539);
    final yaourt = Product(id: 'y', name: 'Yaourt', unit: 'pièce', kcal100: 60, packQty: 125, packUnit: 'g');
    final lait = Product(id: 'l', name: 'Lait', unit: 'L', kcal100: 46);
    expect(kcalOf(nutella, 15, 'g'), closeTo(80.85, 1e-9));
    expect(kcalOf(yaourt, 2, 'pièce'), 150);
    expect(kcalOf(lait, 0.5, 'L'), 230);
    expect(kcalOf(Product(name: 'x', unit: 'pièce', kcal100: 50), 1, 'pièce'), isNull);
    final r = Recipe(name: 'Gâteau', servings: 4, ingredients: [
      RecipeIngredient(name: 'Yaourt', quantity: 2, productId: 'y'),
      RecipeIngredient(name: 'Lait', quantity: 500, unit: 'ml'),
      RecipeIngredient(name: 'Sel', quantity: 1, unit: 'g'),
    ]);
    final k = recipeKcal(r, [nutella, yaourt, lait]);
    expect(k.total, 380);
    expect(k.perPerson, 95);
    expect(k.unknown, 1);
    final k8 = recipeKcal(r, [nutella, yaourt, lait], people: 8);
    expect(k8.total, 760);
    expect(k8.perPerson, 95);
  });

  test('portions : besoins proportionnels au nombre de personnes', () {
    final r = Recipe(id: 'r', name: 'Crêpes', servings: 4, ingredients: [
      RecipeIngredient(name: 'Farine', quantity: 250, unit: 'g'),
    ]);
    List<Need> n(int? people) => computeNeeds(
        plan: [MealPlanEntry(recipeId: 'r', people: people)], recipes: {'r': r}, products: [], batches: [], today: today);
    expect(n(2).single.needed, 125);
    expect(n(8).single.needed, 500);
    expect(n(null).single.needed, 250);
  });

  test('congelé : la date ne compte plus, les lots frais partent en premier', () {
    final p = Product(id: 'v', name: 'Viande', unit: 'g');
    final lots = [
      Batch(id: 'f', productId: 'v', quantity: 500, expirationDate: DateTime(2026, 11, 1), frozen: true),
      Batch(id: 'a', productId: 'v', quantity: 200, expirationDate: DateTime(2026, 11, 25)),
    ];
    expect(availableQuantity(p, lots, 'g', today: today), 700);
    expect(sortFefo(lots).map((b) => b.id), ['a', 'f']);
    expect(consumeFefo(lots, 300).newQuantities, {'a': 0, 'f': 400});
  });

  test('stock minimum : ajouté aux besoins et à la liste de courses', () {
    final pates = Product(id: 'p', name: 'Pâtes', unit: 'pièce', minQty: 2);
    final riz = Product(id: 'r', name: 'Riz', unit: 'kg', minQty: 1);
    final batches = [
      Batch(productId: 'p', quantity: 1, expirationDate: DateTime(2027, 6, 1)),
      Batch(productId: 'r', quantity: 2, expirationDate: DateTime(2027, 6, 1)),
    ];
    expect(belowMinimum([pates, riz], batches, today: today).map((p) => p.id), ['p']);
    final carbo = Recipe(id: 'c', name: 'Carbo', ingredients: [RecipeIngredient(name: 'Pâtes', quantity: 1, productId: 'p')]);
    final needs = addMinStock(
      computeNeeds(plan: [MealPlanEntry(recipeId: 'c')], recipes: {'c': carbo}, products: [pates, riz], batches: batches, today: today),
      [pates, riz],
      batches,
      today: today,
    );
    final p = needs.firstWhere((n) => n.name == 'Pâtes');
    expect(p.needed, 3);
    expect(p.missing, 2);
    expect(needs.firstWhere((n) => n.name == 'Riz').isMissing, isFalse);
    final list = regenerateShopping([], needs);
    expect(list.single.why, 'both');
  });

  test('dates lues sur une photo : seulement si elles sont vraiment écrites', () {
    List<String> d(String t) => findDates(t, today: today).map((x) => dateToKey(x.date)).toList();
    expect(d("A consommer jusqu'au 12/05/2027 L1234"), ['2027-05-12']);
    expect(d('DLC 03.12.26'), ['2026-12-03']);
    expect(d('à consommer de préférence avant le 15 MAI 2027'), ['2027-05-15']);
    expect(d('A consommer de préférence avant fin : 06/2027'), ['2027-06-30']);
    expect(findDates('fin 06/2027', today: today).single.monthOnly, isTrue);
    expect(d('31/02/2027'), isEmpty);
    expect(d('LOT 3017620422003 18:45'), isEmpty);
    expect(d('12/05/1998'), isEmpty);
    expect(d('Le 01/12/2026 et le 05/12/2026'), ['2026-12-01', '2026-12-05']);
  });

  test('base embarquée : calories et contenance', () {
    final p = LocalProducts.parseLine('3017620422003', 'Nutella\tFerrero\t2\t400 g\tfront_en.879.200.jpg\t539');
    expect(p.kcal100, 539);
    expect(p.pack!.each, 400);
    expect(p.local, isTrue);
    expect(LocalProducts.parseLine('1', 'Eau\t\t4\t\t').kcal100, isNull);
  });

  group('Base de données', () {
    var n = 0;
    late AppState state;
    setUp(() async => state = await AppState.open(factory: databaseFactoryMemory, name: 'nf${n++}.db'));

    test('paquet entamé automatiquement, congeler puis décongeler', () async {
      await state.addStock(name: 'Nutella', category: 'Épicerie', unit: 'g', quantity: 400,
          expiration: DateTime.now().add(const Duration(days: 100)), kcal100: 539);
      final id = state.products.keys.first;
      await state.consume(id, 100);
      final lot = state.batchesOf(id).single;
      expect(lot.quantity, 300);
      expect(lot.opened, isTrue);
      await state.freezeBatch(lot);
      expect(state.expiringBatches, isEmpty);
      await state.thawBatch(lot);
      expect(lot.frozen, isFalse);
      expect(daysUntil(lot.expirationDate), 1);
    });

    test('stock minimum → liste de courses automatique', () async {
      await state.addStock(name: 'Pâtes', category: 'Épicerie', unit: 'pièce', quantity: 1,
          expiration: DateTime.now().add(const Duration(days: 300)));
      final p = state.products.values.single..minQty = 2;
      await state.saveProduct(p);
      expect(state.shopping.values.single.why, 'min');
      expect(state.shopping.values.single.quantity, 1);
    });

    test('recette faite pour 2 au lieu de 4 : moitié des quantités retirées', () async {
      await state.addStock(name: 'Oeufs', category: 'Frais', unit: 'pièce', quantity: 6,
          expiration: DateTime.now().add(const Duration(days: 10)));
      final r = Recipe(name: 'Omelette', servings: 4, ingredients: [RecipeIngredient(name: 'oeufs', quantity: 4)]);
      await state.consumeRecipe(r, people: 2);
      expect(state.totalOf(state.products.keys.first), 4);
    });

    test('anciennes sauvegardes (sans nouveaux champs) toujours lisibles', () async {
      const old = '{"format":"stock_alimentaire_backup","version":1,"settings":{"alertDays":3},'
          '"products":[{"id":"p","name":"Riz","category":"Épicerie","unit":"kg"}],'
          '"batches":[{"id":"b","productId":"p","quantity":1,"expirationDate":"2027-01-01"}],'
          '"recipes":[],"plan":[],"shopping":[]}';
      await state.importJson(old);
      expect(state.products['p']!.kcal100, isNull);
      expect(state.batches['b']!.frozen, isFalse);
      expect(state.settings.useLocations, isFalse);
    });
  });
}
