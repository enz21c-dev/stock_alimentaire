import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sembast/sembast.dart';

import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import 'db_factory_memory.dart' if (dart.library.js_interop) 'db_factory_web.dart';

/// Ce qu'il faut pour annuler une suppression / consommation.
class UndoSnapshot {
  final List<Batch> batches;
  final Product? product;
  UndoSnapshot(this.batches, [this.product]);
}

/// État de l'application : toutes les données, chargées en mémoire et
/// enregistrées sur l'appareil (IndexedDB dans le navigateur).
class AppState extends ChangeNotifier {
  AppState._(this._db);

  final Database _db;

  static final _productsStore = stringMapStoreFactory.store('products');
  static final _batchesStore = stringMapStoreFactory.store('batches');
  static final _recipesStore = stringMapStoreFactory.store('recipes');
  static final _planStore = stringMapStoreFactory.store('plan');
  static final _shoppingStore = stringMapStoreFactory.store('shopping');
  static final _settingsStore = stringMapStoreFactory.store('settings');

  final Map<String, Product> products = {};
  final Map<String, Batch> batches = {};
  final Map<String, Recipe> recipes = {};
  final Map<String, MealPlanEntry> plan = {};
  final Map<String, ShoppingItem> shopping = {};
  Settings settings = Settings();

  static Future<AppState> open({DatabaseFactory? factory, String name = 'stock_alimentaire.db'}) async {
    final db = await (factory ?? platformDatabaseFactory).openDatabase(name);
    final s = AppState._(db);
    await s._load();
    return s;
  }

  Future<void> _load() async {
    Future<void> load<T>(StoreRef<String, Map<String, Object?>> store, Map<String, T> into,
        T Function(Map<String, Object?>) parse) async {
      into.clear();
      for (final r in await store.find(_db)) {
        into[r.key] = parse(Map<String, Object?>.from(r.value));
      }
    }

    await load(_productsStore, products, Product.fromJson);
    await load(_batchesStore, batches, Batch.fromJson);
    await load(_recipesStore, recipes, Recipe.fromJson);
    await load(_planStore, plan, MealPlanEntry.fromJson);
    await load(_shoppingStore, shopping, ShoppingItem.fromJson);
    final s = await _settingsStore.record('main').get(_db);
    settings = s == null ? Settings() : Settings.fromJson(Map<String, Object?>.from(s));
  }

  Future<void> close() => _db.close();

  // -------------------------------------------------------------------------
  // Lecture
  // -------------------------------------------------------------------------

  List<Batch> batchesOf(String productId) =>
      sortFefo(batches.values.where((b) => b.productId == productId));

  double totalOf(String productId) =>
      batches.values.where((b) => b.productId == productId).fold(0.0, (s, b) => s + b.quantity);

  /// Produits ayant au moins un lot en stock.
  List<Product> get productsInStock {
    final ids = batches.values.map((b) => b.productId).toSet();
    return products.values.where((p) => ids.contains(p.id)).toList();
  }

  Product? productByBarcode(String barcode) {
    for (final p in products.values) {
      if (p.barcode == barcode) return p;
    }
    return null;
  }

  Product? productByName(String name) {
    final n = normalizeName(name);
    for (final p in products.values) {
      if (normalizeName(p.name) == n) return p;
    }
    return null;
  }

  /// Lots périmés ou périmant dans le délai d'alerte, du plus urgent au moins urgent.
  List<Batch> get expiringBatches => sortFefo(batches.values.where(
      (b) => daysUntil(b.expirationDate) <= settings.alertDays));

  List<Need> get needs => computeNeeds(
        plan: plan.values,
        recipes: recipes,
        products: products.values.toList(),
        batches: batches.values.toList(),
      );

  // -------------------------------------------------------------------------
  // Stock
  // -------------------------------------------------------------------------

  /// Ajoute un lot. Réutilise le produit existant (même code-barres, sinon
  /// même nom) au lieu d'en créer un doublon.
  Future<Batch> addStock({
    required String name,
    String? brand,
    String? barcode,
    required String category,
    required String unit,
    String? photoUrl,
    String? photoData,
    required double quantity,
    required DateTime expiration,
  }) async {
    Product? product = (barcode != null && barcode.isNotEmpty) ? productByBarcode(barcode) : null;
    product ??= productByName(name);
    if (product != null && barcode != null && barcode.isNotEmpty &&
        product.barcode != null && product.barcode != barcode) {
      product = null; // même nom mais autre produit scanné
    }

    var qty = quantity;
    if (product == null) {
      product = Product(
        name: name.trim(),
        brand: brand,
        barcode: (barcode?.isEmpty ?? true) ? null : barcode,
        category: category,
        unit: unit,
        photoUrl: photoUrl,
        photoData: photoData,
      );
    } else {
      product.category = category;
      product.brand = brand ?? product.brand;
      if (barcode != null && barcode.isNotEmpty) product.barcode = barcode;
      if (photoUrl != null) product.photoUrl = photoUrl;
      if (photoData != null) product.photoData = photoData;
      // Quantité convertie dans l'unité du produit si possible (500 g → 0,5 kg).
      final converted = convert(quantity, unit, product.unit);
      if (converted != null) {
        qty = converted;
      } else if (totalOf(product.id) == 0) {
        product.unit = unit;
      }
    }
    final batch = Batch(productId: product.id, quantity: qty, expirationDate: expiration);
    products[product.id] = product;
    batches[batch.id] = batch;
    notifyListeners();
    await _db.transaction((t) async {
      await _productsStore.record(product!.id).put(t, product.toJson());
      await _batchesStore.record(batch.id).put(t, batch.toJson());
    });
    await _syncShopping();
    return batch;
  }

  Future<void> saveProduct(Product p) async {
    products[p.id] = p;
    notifyListeners();
    await _productsStore.record(p.id).put(_db, p.toJson());
  }

  Future<void> saveBatch(Batch b) async {
    batches[b.id] = b;
    notifyListeners();
    await _batchesStore.record(b.id).put(_db, b.toJson());
    await _syncShopping();
  }

  /// Applique de nouvelles quantités (0 = suppression du lot).
  Future<void> _applyQuantities(Map<String, double> q) async {
    await _db.transaction((t) async {
      for (final e in q.entries) {
        final b = batches[e.key];
        if (b == null) continue;
        if (e.value <= 0) {
          batches.remove(b.id);
          await _batchesStore.record(b.id).delete(t);
        } else {
          b.quantity = e.value;
          await _batchesStore.record(b.id).put(t, b.toJson());
        }
      }
    });
    notifyListeners();
    await _syncShopping();
  }

  /// Consomme [quantity] d'un produit en commençant par le lot qui périme le
  /// plus tôt. Renvoie de quoi annuler.
  Future<UndoSnapshot> consume(String productId, double quantity) async {
    final lots = batchesOf(productId);
    final snap = UndoSnapshot(lots.map((b) => b.copy()).toList());
    await _applyQuantities(consumeFefo(lots, quantity).newQuantities);
    return snap;
  }

  Future<UndoSnapshot> deleteBatch(String batchId) async {
    final b = batches[batchId];
    if (b == null) return UndoSnapshot([]);
    final snap = UndoSnapshot([b.copy()]);
    await _applyQuantities({batchId: 0});
    return snap;
  }

  /// Supprime tous les lots d'un produit (le produit reste connu pour le scan).
  Future<UndoSnapshot> deleteAllBatches(String productId) async {
    final lots = batchesOf(productId);
    final snap = UndoSnapshot(lots.map((b) => b.copy()).toList());
    await _applyQuantities({for (final b in lots) b.id: 0});
    return snap;
  }

  Future<void> undo(UndoSnapshot snap) async {
    await _db.transaction((t) async {
      if (snap.product != null) {
        products[snap.product!.id] = snap.product!;
        await _productsStore.record(snap.product!.id).put(t, snap.product!.toJson());
      }
      for (final b in snap.batches) {
        batches[b.id] = b.copy();
        await _batchesStore.record(b.id).put(t, b.toJson());
      }
    });
    notifyListeners();
    await _syncShopping();
  }

  /// Décrémente le stock des ingrédients d'une recette. Renvoie de quoi annuler.
  Future<UndoSnapshot> consumeRecipe(Recipe recipe) async {
    final all = products.values.toList();
    final touched = <String, Batch>{};
    final newQ = <String, double>{};
    for (final ing in recipe.ingredients) {
      final p = matchProduct(ing, all);
      if (p == null) continue;
      final q = convert(ing.quantity, ing.unit, p.unit);
      if (q == null) continue;
      // Lots avec les quantités déjà décrémentées par un ingrédient précédent.
      final lots = batchesOf(p.id).map((b) {
        touched.putIfAbsent(b.id, () => b.copy());
        return Batch(
          id: b.id,
          productId: b.productId,
          quantity: newQ[b.id] ?? b.quantity,
          expirationDate: b.expirationDate,
          addedDate: b.addedDate,
        );
      }).where((b) => b.quantity > 0);
      newQ.addAll(consumeFefo(lots, q).newQuantities);
    }
    final snap = UndoSnapshot(touched.values.toList());
    await _applyQuantities(newQ);
    return snap;
  }

  // -------------------------------------------------------------------------
  // Recettes, planning, courses
  // -------------------------------------------------------------------------

  Future<void> saveRecipe(Recipe r) async {
    recipes[r.id] = r;
    notifyListeners();
    await _recipesStore.record(r.id).put(_db, r.toJson());
    await _syncShopping();
  }

  Future<void> deleteRecipe(String id) async {
    recipes.remove(id);
    final entries = plan.values.where((e) => e.recipeId == id).map((e) => e.id).toList();
    for (final e in entries) {
      plan.remove(e);
    }
    notifyListeners();
    await _db.transaction((t) async {
      await _recipesStore.record(id).delete(t);
      for (final e in entries) {
        await _planStore.record(e).delete(t);
      }
    });
    await _syncShopping();
  }

  Future<void> savePlanEntry(MealPlanEntry e) async {
    plan[e.id] = e;
    notifyListeners();
    await _planStore.record(e.id).put(_db, e.toJson());
    await _syncShopping();
  }

  Future<void> deletePlanEntry(String id) async {
    plan.remove(id);
    notifyListeners();
    await _planStore.record(id).delete(_db);
    await _syncShopping();
  }

  /// Retire du planning les recettes déjà faites.
  Future<void> clearDonePlan() async {
    final ids = plan.values.where((e) => e.done).map((e) => e.id).toList();
    for (final id in ids) {
      plan.remove(id);
    }
    notifyListeners();
    await _planStore.records(ids).delete(_db);
    await _syncShopping();
  }

  Future<void> saveShoppingItem(ShoppingItem i) async {
    shopping[i.id] = i;
    notifyListeners();
    await _shoppingStore.record(i.id).put(_db, i.toJson());
  }

  Future<void> deleteShoppingItems(Iterable<String> ids) async {
    final list = ids.toList();
    for (final id in list) {
      shopping.remove(id);
    }
    notifyListeners();
    await _shoppingStore.records(list).delete(_db);
  }

  /// Garde la liste de courses à jour quand le stock ou le planning change.
  Future<void> _syncShopping() async {
    if (plan.isEmpty && !shopping.values.any((i) => i.auto)) return;
    await refreshShoppingFromPlan();
  }

  /// Met à jour les lignes automatiques de la liste de courses d'après le planning.
  Future<void> refreshShoppingFromPlan() async {
    final updated = regenerateShopping(shopping.values.toList(), needs);
    final removed = shopping.keys.toSet().difference(updated.map((i) => i.id).toSet());
    shopping
      ..clear()
      ..addEntries(updated.map((i) => MapEntry(i.id, i)));
    notifyListeners();
    await _db.transaction((t) async {
      await _shoppingStore.records(removed.toList()).delete(t);
      for (final i in updated) {
        await _shoppingStore.record(i.id).put(t, i.toJson());
      }
    });
  }

  // -------------------------------------------------------------------------
  // Paramètres
  // -------------------------------------------------------------------------

  Future<void> saveSettings() async {
    notifyListeners();
    await _settingsStore.record('main').put(_db, settings.toJson());
  }

  /// Renomme une catégorie partout.
  Future<void> renameCategory(String oldName, String newName) async {
    final i = settings.categories.indexOf(oldName);
    if (i < 0) return;
    settings.categories[i] = newName;
    final changed = products.values.where((p) => p.category == oldName).toList();
    for (final p in changed) {
      p.category = newName;
    }
    await _db.transaction((t) async {
      for (final p in changed) {
        await _productsStore.record(p.id).put(t, p.toJson());
      }
    });
    await saveSettings();
  }

  // -------------------------------------------------------------------------
  // Sauvegarde (export / import JSON)
  // -------------------------------------------------------------------------

  static const backupFormat = 'stock_alimentaire_backup';

  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'format': backupFormat,
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': settings.toJson(),
        'products': products.values.map((e) => e.toJson()).toList(),
        'batches': batches.values.map((e) => e.toJson()).toList(),
        'recipes': recipes.values.map((e) => e.toJson()).toList(),
        'plan': plan.values.map((e) => e.toJson()).toList(),
        'shopping': shopping.values.map((e) => e.toJson()).toList(),
      });

  /// Remplace toutes les données par celles du fichier. Lève une
  /// [FormatException] si le fichier n'est pas une sauvegarde valide.
  Future<void> importJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const FormatException("Ce fichier n'est pas un fichier JSON valide.");
    }
    if (decoded is! Map || decoded['format'] != backupFormat) {
      throw const FormatException("Ce fichier n'est pas une sauvegarde de Stock Alimentaire.");
    }
    List<Map<String, Object?>> list(String k) =>
        ((decoded as Map)[k] as List? ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();

    // On vérifie que tout se lit correctement AVANT d'effacer quoi que ce soit.
    final Settings newSettings;
    final List<Product> ps;
    final List<Batch> bs;
    final List<Recipe> rs;
    final List<MealPlanEntry> es;
    final List<ShoppingItem> ss;
    try {
      newSettings = Settings.fromJson(Map<String, Object?>.from(decoded['settings'] as Map? ?? {}));
      ps = list('products').map(Product.fromJson).toList();
      bs = list('batches').map(Batch.fromJson).toList();
      rs = list('recipes').map(Recipe.fromJson).toList();
      es = list('plan').map(MealPlanEntry.fromJson).toList();
      ss = list('shopping').map(ShoppingItem.fromJson).toList();
    } catch (_) {
      throw const FormatException('Le fichier de sauvegarde est abîmé ou incomplet.');
    }

    await _db.transaction((t) async {
      for (final s in [_productsStore, _batchesStore, _recipesStore, _planStore, _shoppingStore]) {
        await s.delete(t);
      }
      for (final p in ps) {
        await _productsStore.record(p.id).put(t, p.toJson());
      }
      for (final b in bs) {
        await _batchesStore.record(b.id).put(t, b.toJson());
      }
      for (final r in rs) {
        await _recipesStore.record(r.id).put(t, r.toJson());
      }
      for (final e in es) {
        await _planStore.record(e.id).put(t, e.toJson());
      }
      for (final s in ss) {
        await _shoppingStore.record(s.id).put(t, s.toJson());
      }
      await _settingsStore.record('main').put(t, newSettings.toJson());
    });
    await _load();
    notifyListeners();
  }
}

/// Donne accès à l'état depuis n'importe quel écran : `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Sans s'abonner aux changements (pour les actions).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
