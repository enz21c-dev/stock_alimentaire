// Logique « métier » pure (sans interface), testée dans test/.

import '../models/models.dart';
import 'units.dart';

// ---------------------------------------------------------------------------
// Péremption
// ---------------------------------------------------------------------------

enum ExpiryStatus { ok, soon, expired }

/// Jours restants avant la date (0 = périme aujourd'hui, négatif = périmé).
int daysUntil(DateTime expiration, {DateTime? today}) {
  final t = dateOnly(today ?? DateTime.now());
  final e = dateOnly(expiration);
  // Calcul en UTC pour ignorer les changements d'heure.
  return DateTime.utc(e.year, e.month, e.day)
      .difference(DateTime.utc(t.year, t.month, t.day))
      .inDays;
}

/// Vert si > [alertDays] jours, orange si ≤ [alertDays], rouge si périmé.
ExpiryStatus expiryStatus(int days, {int alertDays = 3}) {
  if (days < 0) return ExpiryStatus.expired;
  if (days <= alertDays) return ExpiryStatus.soon;
  return ExpiryStatus.ok;
}

String expiryLabel(int days) {
  if (days < -1) return 'périmé depuis ${-days} jours';
  if (days == -1) return 'périmé depuis hier';
  if (days == 0) return "périme aujourd'hui";
  if (days == 1) return 'périme demain';
  return 'dans $days jours';
}

/// Trie les lots du plus proche au plus lointain (FEFO).
List<Batch> sortFefo(Iterable<Batch> batches) {
  final list = batches.toList()
    ..sort((a, b) {
      final c = a.expirationDate.compareTo(b.expirationDate);
      return c != 0 ? c : a.addedDate.compareTo(b.addedDate);
    });
  return list;
}

// ---------------------------------------------------------------------------
// Consommation FEFO (premier périmé, premier sorti)
// ---------------------------------------------------------------------------

class ConsumeResult {
  /// Nouvelle quantité de chaque lot touché (0 = lot à supprimer).
  final Map<String, double> newQuantities;

  /// Quantité demandée qui n'a pas pu être prise (stock insuffisant).
  final double missing;

  const ConsumeResult(this.newQuantities, this.missing);
}

ConsumeResult consumeFefo(Iterable<Batch> batches, double quantity) {
  var remaining = quantity;
  final result = <String, double>{};
  for (final b in sortFefo(batches)) {
    if (remaining <= 1e-9) break;
    final take = b.quantity < remaining ? b.quantity : remaining;
    final left = b.quantity - take;
    result[b.id] = left < 1e-9 ? 0 : left;
    remaining -= take;
  }
  return ConsumeResult(result, remaining < 1e-9 ? 0 : remaining);
}

// ---------------------------------------------------------------------------
// Besoins des recettes planifiées comparés au stock
// ---------------------------------------------------------------------------

class Need {
  final String name;
  final String unit; // unité de base : g, ml ou pièce
  final Product? product;
  double needed;
  double available;

  Need({required this.name, required this.unit, this.product, this.needed = 0, this.available = 0});

  double get missing => needed - available > 1e-9 ? needed - available : 0;
  bool get isMissing => missing > 0;
}

/// Trouve le produit du stock correspondant à un ingrédient.
Product? matchProduct(RecipeIngredient ing, List<Product> products) {
  if (ing.productId != null) {
    for (final p in products) {
      if (p.id == ing.productId) return p;
    }
  }
  final n = normalizeName(ing.name);
  if (n.isEmpty) return null;
  for (final p in products) {
    if (normalizeName(p.name) == n) return p;
  }
  // Ex. ingrédient « yaourt » ↔ produit « Yaourt nature bio ».
  for (final p in products) {
    final pn = normalizeName(p.name);
    if (pn.startsWith('$n ')) return p;
  }
  return null;
}

/// Quantité disponible (non périmée) d'un produit, exprimée dans [unit].
double availableQuantity(Product p, List<Batch> batches, String unit, {DateTime? today}) {
  var total = 0.0;
  for (final b in batches) {
    if (b.productId != p.id) continue;
    if (daysUntil(b.expirationDate, today: today) < 0) continue;
    total += convert(b.quantity, p.unit, unit) ?? 0;
  }
  return total;
}

/// Cumule les ingrédients des recettes planifiées (non faites) et les compare
/// au stock. Les besoins sont triés : manquants d'abord, puis par nom.
List<Need> computeNeeds({
  required Iterable<MealPlanEntry> plan,
  required Map<String, Recipe> recipes,
  required List<Product> products,
  required List<Batch> batches,
  DateTime? today,
}) {
  final needs = <String, Need>{};
  for (final entry in plan) {
    if (entry.done) continue;
    final recipe = recipes[entry.recipeId];
    if (recipe == null) continue;
    for (final ing in recipe.ingredients) {
      final product = matchProduct(ing, products);
      final base = baseUnit(ing.unit);
      final key = '${product?.id ?? normalizeName(ing.name)}|$base';
      final need = needs.putIfAbsent(
        key,
        () => Need(
          name: product?.name ?? ing.name.trim(),
          unit: base,
          product: product,
          available: product == null
              ? 0
              : availableQuantity(product, batches, base, today: today),
        ),
      );
      need.needed += convert(ing.quantity, ing.unit, base)!;
    }
  }
  final list = needs.values.toList()
    ..sort((a, b) {
      if (a.isMissing != b.isMissing) return a.isMissing ? -1 : 1;
      return normalizeName(a.name).compareTo(normalizeName(b.name));
    });
  return list;
}

// ---------------------------------------------------------------------------
// Liste de courses
// ---------------------------------------------------------------------------

/// Recalcule la liste de courses : garde les articles ajoutés à la main et
/// ceux déjà cochés, remplace les lignes automatiques par les manques actuels
/// (quantités cumulées sur toutes les recettes prévues).
List<ShoppingItem> regenerateShopping(List<ShoppingItem> current, List<Need> needs) {
  final kept = current.where((i) => !i.auto || i.checked).toList();
  final keptNames = kept.where((i) => i.auto).map((i) => normalizeName(i.name)).toSet();
  // Réutilise l'identifiant des lignes automatiques existantes (moins d'écritures).
  final previous = {
    for (final i in current.where((i) => i.auto && !i.checked)) '${normalizeName(i.name)}|${i.unit}': i.id,
  };
  final added = <ShoppingItem>[];
  for (final n in needs) {
    if (!n.isMissing) continue;
    if (keptNames.contains(normalizeName(n.name))) continue;
    final (q, u) = humanize(n.missing, n.unit);
    added.add(ShoppingItem(
      id: previous['${normalizeName(n.name)}|$u'],
      name: n.name,
      quantity: q,
      unit: u,
      auto: true,
    ));
  }
  return [...added, ...kept];
}
