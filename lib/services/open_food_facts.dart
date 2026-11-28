import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/stock_logic.dart';

/// Infos produit trouvées sur Open Food Facts (ou dans la base embarquée).
class OffProduct {
  final String barcode;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String category;
  final double? quantity;
  final String? unit;
  final String? quantityText; // contenance telle qu'écrite (« 4 x 125 g »)
  final Pack? pack;
  final double? kcal100;
  final bool local; // trouvé dans la base embarquée (sans internet)

  OffProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    required this.category,
    this.quantity,
    this.unit,
    this.quantityText,
    this.pack,
    this.kcal100,
    this.local = false,
  });
}

// Étiquettes trop générales ignorées : « plant-based-foods-and-BEVERAGES »,
// « fruit-based-foods-and-beverages »… classaient pâtes ou confiture dans
// Boissons. Mêmes règles que tools/build_products.py et lite/logic.js.
const _ignoredTags = {
  'en:plant-based-foods-and-beverages',
  'en:plant-based-foods',
  'en:beverages-and-beverages-preparations',
};

/// Associe les catégories Open Food Facts aux catégories de l'appli.
String mapOffCategory(List<String> allTags) {
  final tags = allTags.where((t) => !_ignoredTags.contains(t) && !t.contains('foods-and-beverages')).toList();
  bool has(List<String> keys) => tags.any((t) => keys.any((k) => t.contains(k)));
  if (has(['frozen'])) return 'Surgelé';
  if (has(['beverages', 'drinks', 'waters', 'juices', 'sodas', 'wines', 'beers', 'ciders', 'spirits',
      'alcoholic', 'nectars', 'plant-milks'])) {
    return 'Boissons';
  }
  if (has(['canned'])) return 'Conserves';
  if (has(['dairies', 'dairy', 'yogurts', 'cheeses', 'meats', 'fresh', 'eggs', 'fishes', 'butters', 'creams',
      'hams', 'sausages', 'refrigerated', 'chilled', 'charcuteries', 'poultries', 'seafood', 'fermented-milk'])) {
    return 'Frais';
  }
  if (tags.isEmpty) return 'Autre';
  return 'Épicerie';
}

/// Lit une quantité OFF du type « 500 g », « 1,5 L », « 4 x 125 g » (total).
(double, String)? parseOffQuantity(String? s) {
  final p = parsePack(s);
  if (p == null) return null;
  return (p.each * p.count, p.unit);
}

/// Calories pour 100 g/ml à partir des données nutritionnelles.
double? kcalFromNutriments(Object? n) {
  if (n is! Map) return null;
  var k = n['energy-kcal_100g'];
  if (k is! num && n['energy_100g'] is num) k = (n['energy_100g'] as num) / 4.184; // kJ → kcal
  return (k is num && k >= 0 && k < 1000) ? k.roundToDouble() : null;
}

class OpenFoodFacts {
  static const _fields =
      'product_name,product_name_fr,generic_name_fr,brands,image_front_small_url,image_front_url,categories_tags,quantity,nutriments';

  /// Renvoie null si le produit est inconnu. Lève une exception si le réseau échoue.
  static Future<OffProduct?> lookup(String barcode, {http.Client? client}) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode.json', {
      'fields': _fields,
      'lc': 'fr',
    });
    final c = client ?? http.Client();
    try {
      final res = await c.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw Exception('Erreur ${res.statusCode}');
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (body['status'] != 1 || body['product'] == null) return null;
      final p = body['product'] as Map<String, dynamic>;
      String? str(String k) {
        final v = p[k];
        return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
      }

      final name = str('product_name_fr') ?? str('product_name') ?? str('generic_name_fr');
      if (name == null) return null;
      final q = parseOffQuantity(str('quantity'));
      return OffProduct(
        barcode: barcode,
        name: name,
        brand: str('brands')?.split(',').first.trim(),
        imageUrl: str('image_front_small_url') ?? str('image_front_url'),
        category: mapOffCategory(((p['categories_tags'] as List?) ?? const []).cast<String>()),
        quantity: q?.$1,
        unit: q?.$2,
        quantityText: str('quantity'),
        pack: parsePack(str('quantity')),
        kcal100: kcalFromNutriments(p['nutriments']),
      );
    } finally {
      if (client == null) c.close();
    }
  }
}
