import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/models.dart';
import 'open_food_facts.dart';

/// Base de ~60 000 produits courants en France, embarquée dans l'appli
/// (même fichier que la version légère : lite/data/products-fr.tsv).
/// Permet de reconnaître un produit scanné sans internet.
class LocalProducts {
  LocalProducts._();

  static Map<String, String>? _map;
  static Future<Map<String, String>>? _loading;

  static Future<Map<String, String>> _load() {
    if (_map != null) return Future.value(_map);
    return _loading ??= rootBundle.loadString('lite/data/products-fr.tsv').then((text) {
      final m = <String, String>{};
      for (final line in const LineSplitter().convert(text)) {
        final i = line.indexOf('\t');
        if (i > 0) m[line.substring(0, i)] = line.substring(i + 1);
      }
      return _map = m;
    });
  }

  /// Précharge la base en arrière-plan (scan instantané ensuite).
  static void preload() => _load().catchError((_) => <String, String>{});

  static Future<OffProduct?> lookup(String code) async {
    final Map<String, String> map;
    try {
      map = await _load();
    } catch (_) {
      return null;
    }
    final line = map[code];
    if (line == null) return null;
    return parseLine(code, line);
  }

  /// Ligne : nom, marque, n° catégorie, contenance, fin de l'URL de la photo.
  static OffProduct parseLine(String code, String line) {
    final f = line.split('\t');
    String at(int i) => i < f.length ? f[i] : '';
    final cat = int.tryParse(at(2)) ?? 5;
    final q = parseOffQuantity(at(3));
    return OffProduct(
      barcode: code,
      name: at(0),
      brand: at(1).isEmpty ? null : at(1),
      category: cat >= 0 && cat < defaultCategories.length ? defaultCategories[cat] : 'Autre',
      imageUrl: imageUrl(code, at(4)),
      quantity: q?.$1,
      unit: q?.$2,
    );
  }

  static String? imageUrl(String code, String file) {
    if (file.isEmpty) return null;
    var folder = code;
    if (code.length > 8) {
      final c = code.padLeft(13, '0');
      folder = '${c.substring(0, 3)}/${c.substring(3, 6)}/${c.substring(6, 9)}/${c.substring(9)}';
    }
    return 'https://images.openfoodfacts.org/images/products/$folder/$file';
  }
}
