// Modèles de données de l'application.
//
// Toutes les dates « jour » (péremption, planning) sont stockées au format
// texte AAAA-MM-JJ pour éviter les problèmes de fuseau horaire.
// Les champs ajoutés après la version 1.0 sont facultatifs : les anciennes
// données restent lisibles.

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
double? _toDoubleOrNull(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _keyOrNull(Object? v) => v is String && v.length >= 10 ? dateFromKey(v) : null;

/// Un produit (ex. « Yaourt nature »). Il peut avoir plusieurs lots.
class Product {
  final String id;
  String name;
  String? brand;
  String? barcode; // code EAN, null si ajouté à la main
  String category;
  String unit; // pièce, g, kg, ml, L
  String? photoUrl; // image Open Food Facts
  String? photoData; // photo prise avec l'appareil (JPEG en base64)
  double? kcal100; // calories pour 100 g ou 100 ml
  double? packQty; // poids/volume d'une pièce (pour les calories), ex. 125
  String? packUnit; // g, kg, ml, L
  double? minQty; // stock minimum, dans l'unité du produit

  Product({
    String? id,
    required this.name,
    this.brand,
    this.barcode,
    this.category = 'Autre',
    this.unit = 'pièce',
    this.photoUrl,
    this.photoData,
    this.kcal100,
    this.packQty,
    this.packUnit,
    this.minQty,
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
        'kcal100': kcal100,
        'packQty': packQty,
        'packUnit': packUnit,
        'minQty': minQty,
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
        kcal100: _toDoubleOrNull(m['kcal100']),
        packQty: _toDoubleOrNull(m['packQty']),
        packUnit: m['packUnit'] as String?,
        minQty: _toDoubleOrNull(m['minQty']),
      );
}

/// Un lot : une quantité d'un produit avec sa propre date de péremption.
class Batch {
  final String id;
  final String productId;
  double quantity; // dans l'unité du produit
  DateTime expirationDate;
  DateTime addedDate;
  bool opened; // entamé
  DateTime? openedAt;
  bool frozen; // congelé : la date de péremption ne compte plus
  DateTime? frozenAt;
  String? location; // emplacement (frigo, congélateur…), facultatif

  Batch({
    String? id,
    required this.productId,
    required this.quantity,
    required DateTime expirationDate,
    DateTime? addedDate,
    this.opened = false,
    this.openedAt,
    this.frozen = false,
    this.frozenAt,
    this.location,
  })  : id = id ?? newId(),
        expirationDate = dateOnly(expirationDate),
        addedDate = addedDate ?? DateTime.now();

  Batch copy() => Batch.fromJson(toJson());

  Map<String, Object?> toJson() => {
        'id': id,
        'productId': productId,
        'quantity': quantity,
        'expirationDate': dateToKey(expirationDate),
        'addedDate': addedDate.toIso8601String(),
        'opened': opened,
        'openedAt': openedAt == null ? null : dateToKey(openedAt!),
        'frozen': frozen,
        'frozenAt': frozenAt == null ? null : dateToKey(frozenAt!),
        'location': location,
      };

  factory Batch.fromJson(Map<String, Object?> m) => Batch(
        id: m['id'] as String,
        productId: m['productId'] as String,
        quantity: _toDouble(m['quantity']),
        expirationDate: dateFromKey(m['expirationDate'] as String),
        addedDate: DateTime.tryParse('${m['addedDate']}') ?? DateTime.now(),
        opened: (m['opened'] as bool?) ?? false,
        openedAt: _keyOrNull(m['openedAt']),
        frozen: (m['frozen'] as bool?) ?? false,
        frozenAt: _keyOrNull(m['frozenAt']),
        location: m['location'] as String?,
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

  RecipeIngredient scaled(double f) =>
      RecipeIngredient(name: name, quantity: quantity * f, unit: unit, productId: productId);

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
  int? servings; // nombre de personnes pour les quantités saisies

  Recipe({
    String? id,
    required this.name,
    List<RecipeIngredient>? ingredients,
    this.instructions = '',
    this.photoData,
    this.servings,
  })  : id = id ?? newId(),
        ingredients = ingredients ?? [];

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'instructions': instructions,
        'photoData': photoData,
        'servings': servings,
      };

  factory Recipe.fromJson(Map<String, Object?> m) => Recipe(
        id: m['id'] as String,
        name: m['name'] as String,
        ingredients: ((m['ingredients'] as List?) ?? const [])
            .map((e) => RecipeIngredient.fromJson(Map<String, Object?>.from(e as Map)))
            .toList(),
        instructions: (m['instructions'] as String?) ?? '',
        photoData: m['photoData'] as String?,
        servings: (m['servings'] as num?)?.toInt(),
      );
}

/// Une recette planifiée. [date] est null en mode « liste libre ».
class MealPlanEntry {
  final String id;
  String recipeId;
  DateTime? date;
  bool done;
  int? people; // nombre de personnes (null = celui de la recette)

  MealPlanEntry({String? id, required this.recipeId, DateTime? date, this.done = false, this.people})
      : id = id ?? newId(),
        date = date == null ? null : dateOnly(date);

  Map<String, Object?> toJson() => {
        'id': id,
        'recipeId': recipeId,
        'date': date == null ? null : dateToKey(date!),
        'done': done,
        'people': people,
      };

  factory MealPlanEntry.fromJson(Map<String, Object?> m) => MealPlanEntry(
        id: m['id'] as String,
        recipeId: m['recipeId'] as String,
        date: m['date'] == null ? null : dateFromKey(m['date'] as String),
        done: (m['done'] as bool?) ?? false,
        people: (m['people'] as num?)?.toInt(),
      );
}

/// Une ligne de la liste de courses.
class ShoppingItem {
  final String id;
  String name;
  double? quantity;
  String? unit;
  bool checked;
  bool auto; // true = générée automatiquement
  String? why; // 'plan', 'min' ou 'both' (lignes automatiques)

  ShoppingItem({
    String? id,
    required this.name,
    this.quantity,
    this.unit,
    this.checked = false,
    this.auto = false,
    this.why,
  }) : id = id ?? newId();

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'checked': checked,
        'auto': auto,
        'why': why,
      };

  factory ShoppingItem.fromJson(Map<String, Object?> m) => ShoppingItem(
        id: m['id'] as String,
        name: m['name'] as String,
        quantity: m['quantity'] == null ? null : _toDouble(m['quantity']),
        unit: m['unit'] as String?,
        checked: (m['checked'] as bool?) ?? false,
        auto: (m['auto'] as bool?) ?? false,
        why: m['why'] as String?,
      );
}

const defaultCategories = ['Frais', 'Surgelé', 'Épicerie', 'Conserves', 'Boissons', 'Autre'];
const defaultLocations = ['Frigo', 'Congélateur', 'Placard', 'Cave'];

class Settings {
  int alertDays;
  List<String> categories;
  bool planByDay; // true = recette par jour, false = liste libre
  bool useLocations; // emplacements activés
  List<String> locations;

  Settings({
    this.alertDays = 3,
    List<String>? categories,
    this.planByDay = true,
    this.useLocations = false,
    List<String>? locations,
  })  : categories = categories ?? List.of(defaultCategories),
        locations = locations ?? List.of(defaultLocations);

  Map<String, Object?> toJson() => {
        'alertDays': alertDays,
        'categories': categories,
        'planByDay': planByDay,
        'useLocations': useLocations,
        'locations': locations,
      };

  factory Settings.fromJson(Map<String, Object?> m) => Settings(
        alertDays: (m['alertDays'] as num?)?.toInt() ?? 3,
        categories: (m['categories'] as List?)?.cast<String>().toList(),
        planByDay: (m['planByDay'] as bool?) ?? true,
        useLocations: (m['useLocations'] as bool?) ?? false,
        locations: (m['locations'] as List?)?.cast<String>().toList(),
      );
}
