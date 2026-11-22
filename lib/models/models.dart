// Modèles de données de l'application.
//
// Toutes les dates « jour » (péremption, planning) sont stockées au format
// texte AAAA-MM-JJ pour éviter les problèmes de fuseau horaire.

import 'dart:math';

final _rng = Random();

/// Génère un identifiant unique (texte), utilisable hors ligne.
String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    _rng.nextInt(1 << 30).toRadixString(36);

/// Ne garde que la date (sans l'heure).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateToKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateFromKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2].substring(0, 2)));
}

double _toDouble(Object? v) => v is num ? v.toDouble() : double.parse('$v');

/// Un produit (ex. « Yaourt nature »). Il peut avoir plusieurs lots.
class Product {
  final String id;
  String name;
  String? brand;
  String? barcode; // code EAN, null si ajouté à la main
  String category;
  String unit; // pièce, g, kg, ml, L
  String? photoUrl; // image Open Food Facts
  String? photoData; // photo prise avec l'iPad (JPEG en base64)

  Product({
    String? id,
    required this.name,
    this.brand,
    this.barcode,
    this.category = 'Autre',
    this.unit = 'pièce',
    this.photoUrl,
    this.photoData,
  }) : id = id ?? newId();

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'barcode': barcode,
        'category': category,
        'unit': unit,
        'photoUrl': photoUrl,
        'photoData': photoData,
      };

  factory Product.fromJson(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        brand: m['brand'] as String?,
        barcode: m['barcode'] as String?,
        category: (m['category'] as String?) ?? 'Autre',
        unit: (m['unit'] as String?) ?? 'pièce',
        photoUrl: m['photoUrl'] as String?,
        photoData: m['photoData'] as String?,
      );
}

/// Un lot : une quantité d'un produit avec sa propre date de péremption.
class Batch {
  final String id;
  final String productId;
  double quantity; // dans l'unité du produit
  DateTime expirationDate;
  DateTime addedDate;

  Batch({
    String? id,
    required this.productId,
    required this.quantity,
    required DateTime expirationDate,
    DateTime? addedDate,
  })  : id = id ?? newId(),
        expirationDate = dateOnly(expirationDate),
        addedDate = addedDate ?? DateTime.now();

  Batch copy() => Batch(
        id: id,
        productId: productId,
        quantity: quantity,
        expirationDate: expirationDate,
        addedDate: addedDate,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'productId': productId,
        'quantity': quantity,
        'expirationDate': dateToKey(expirationDate),
        'addedDate': addedDate.toIso8601String(),
      };

  factory Batch.fromJson(Map<String, Object?> m) => Batch(
        id: m['id'] as String,
        productId: m['productId'] as String,
        quantity: _toDouble(m['quantity']),
        expirationDate: dateFromKey(m['expirationDate'] as String),
        addedDate: DateTime.tryParse('${m['addedDate']}') ?? DateTime.now(),
      );
}

/// Un ingrédient de recette. Relié à un produit du stock si possible,
/// sinon simple texte libre (rapproché par le nom).
class RecipeIngredient {
  String name;
  double quantity;
  String unit;
  String? productId;

  RecipeIngredient({
    required this.name,
    required this.quantity,
    this.unit = 'pièce',
    this.productId,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'productId': productId,
      };

  factory RecipeIngredient.fromJson(Map<String, Object?> m) => RecipeIngredient(
        name: m['name'] as String,
        quantity: _toDouble(m['quantity']),
        unit: (m['unit'] as String?) ?? 'pièce',
        productId: m['productId'] as String?,
      );
}

class Recipe {
  final String id;
  String name;
  List<RecipeIngredient> ingredients;
  String instructions;
  String? photoData;

  Recipe({
    String? id,
    required this.name,
    List<RecipeIngredient>? ingredients,
    this.instructions = '',
    this.photoData,
  })  : id = id ?? newId(),
        ingredients = ingredients ?? [];

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'instructions': instructions,
        'photoData': photoData,
      };

  factory Recipe.fromJson(Map<String, Object?> m) => Recipe(
        id: m['id'] as String,
        name: m['name'] as String,
        ingredients: ((m['ingredients'] as List?) ?? const [])
            .map((e) => RecipeIngredient.fromJson(Map<String, Object?>.from(e as Map)))
            .toList(),
        instructions: (m['instructions'] as String?) ?? '',
        photoData: m['photoData'] as String?,
      );
}

/// Une recette planifiée. [date] est null en mode « liste libre ».
class MealPlanEntry {
  final String id;
  String recipeId;
  DateTime? date;
  bool done;

  MealPlanEntry({String? id, required this.recipeId, DateTime? date, this.done = false})
      : id = id ?? newId(),
        date = date == null ? null : dateOnly(date);

  Map<String, Object?> toJson() => {
        'id': id,
        'recipeId': recipeId,
        'date': date == null ? null : dateToKey(date!),
        'done': done,
      };

  factory MealPlanEntry.fromJson(Map<String, Object?> m) => MealPlanEntry(
        id: m['id'] as String,
        recipeId: m['recipeId'] as String,
        date: m['date'] == null ? null : dateFromKey(m['date'] as String),
        done: (m['done'] as bool?) ?? false,
      );
}

/// Une ligne de la liste de courses.
class ShoppingItem {
  final String id;
  String name;
  double? quantity;
  String? unit;
  bool checked;
  bool auto; // true = générée depuis le planning

  ShoppingItem({
    String? id,
    required this.name,
    this.quantity,
    this.unit,
    this.checked = false,
    this.auto = false,
  }) : id = id ?? newId();

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'checked': checked,
        'auto': auto,
      };

  factory ShoppingItem.fromJson(Map<String, Object?> m) => ShoppingItem(
        id: m['id'] as String,
        name: m['name'] as String,
        quantity: m['quantity'] == null ? null : _toDouble(m['quantity']),
        unit: m['unit'] as String?,
        checked: (m['checked'] as bool?) ?? false,
        auto: (m['auto'] as bool?) ?? false,
      );
}

const defaultCategories = ['Frais', 'Surgelé', 'Épicerie', 'Conserves', 'Boissons', 'Autre'];

class Settings {
  int alertDays;
  List<String> categories;
  bool planByDay; // true = recette par jour, false = liste libre

  Settings({this.alertDays = 3, List<String>? categories, this.planByDay = true})
      : categories = categories ?? List.of(defaultCategories);

  Map<String, Object?> toJson() => {
        'alertDays': alertDays,
        'categories': categories,
        'planByDay': planByDay,
      };

  factory Settings.fromJson(Map<String, Object?> m) => Settings(
        alertDays: (m['alertDays'] as num?)?.toInt() ?? 3,
        categories: (m['categories'] as List?)?.cast<String>().toList(),
        planByDay: (m['planByDay'] as bool?) ?? true,
      );
}
