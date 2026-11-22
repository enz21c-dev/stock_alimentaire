import 'dart:convert';

import 'package:http/http.dart' as http;

/// Infos produit trouvées sur Open Food Facts.
class OffProduct {
  final String barcode;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String category;
  final double? quantity;
  final String? unit;

  OffProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    required this.category,
    this.quantity,
    this.unit,
  });
}

/// Associe les catégories Open Food Facts aux catégories de l'appli.
String mapOffCategory(List<String> tags) {
  bool has(List<String> keys) => tags.any((t) => keys.any((k) => t.contains(k)));
  if (has(['frozen'])) return 'Surgelé';
  if (has(['beverages', 'drinks', 'waters', 'juices', 'sodas', 'wines', 'beers'])) {
    return 'Boissons';
  }
  if (has(['canned'])) return 'Conserves';
  if (has(['dairies', 'dairy', 'yogurts', 'cheeses', 'meats', 'fresh', 'eggs', 'fishes',
      'butters', 'creams', 'hams', 'sausages', 'refrigerated'])) {
    return 'Frais';
  }
  if (tags.isEmpty) return 'Autre';
  return 'Épicerie';
}

/// Lit une quantité OFF du type « 500 g », « 1,5 L », « 4 x 125 g ».
(double, String)? parseOffQuantity(String? s) {
  if (s == null) return null;
  final t = s.toLowerCase().replaceAll(',', '.');
  final m = RegExp(r'(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b').firstMatch(t);
  if (m == null) return null;
  final count = m.group(1) == null ? 1 : int.parse(m.group(1)!);
  var v = double.parse(m.group(2)!) * count;
  var u = m.group(3)!;
  if (u == 'cl') {
    v *= 10;
    u = 'ml';
  }
  if (u == 'l') u = 'L';
  return (v, u);
}

class OpenFoodFacts {
  static const _fields =
      'product_name,product_name_fr,generic_name_fr,brands,image_front_small_url,image_front_url,categories_tags,quantity';

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
      );
    } finally {
      if (client == null) c.close();
    }
  }
}
