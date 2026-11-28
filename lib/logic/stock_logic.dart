// Logique « métier » pure (sans interface), testée dans test/.
// Mêmes règles que la version iPad (lite/logic.js).

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

/// Lots du plus urgent au moins urgent (FEFO) ; les lots congelés en dernier.
List<Batch> sortFefo(Iterable<Batch> batches) {
  final list = batches.toList()
    ..sort((a, b) {
      if (a.frozen != b.frozen) return a.frozen ? 1 : -1;
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
  bool fromPlan;
  bool min;

  Need({
    required this.name,
    required this.unit,
    this.product,
    this.needed = 0,
    this.available = 0,
    this.fromPlan = false,
    this.min = false,
  });

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

/// Quantité disponible d'un produit, exprimée dans [unit] (un lot périmé ne
/// compte pas, sauf s'il est congelé).
double availableQuantity(Product p, List<Batch> batches, String unit, {DateTime? today}) {
  var total = 0.0;
  for (final b in batches) {
    if (b.productId != p.id) continue;
    if (!b.frozen && daysUntil(b.expirationDate, today: today) < 0) continue;
    total += convert(b.quantity, p.unit, unit) ?? 0;
  }
  return total;
}

/// Facteur des portions : recette pour 4, cuisinée pour 2 → 0,5.
double portionFactor(Recipe recipe, int? people) {
  final s = recipe.servings ?? 0;
  return (s > 0 && people != null && people > 0) ? people / s : 1;
}

List<Need> _finishNeeds(List<Need> list) => list
  ..sort((a, b) {
    if (a.isMissing != b.isMissing) return a.isMissing ? -1 : 1;
    return normalizeName(a.name).compareTo(normalizeName(b.name));
  });

/// Cumule les ingrédients des recettes planifiées (non faites, selon le nombre
/// de personnes) et les compare au stock. Manquants d'abord, puis par nom.
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
    final f = portionFactor(recipe, entry.people);
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
          fromPlan: true,
          available: product == null ? 0 : availableQuantity(product, batches, base, today: today),
        ),
      );
      need.needed += convert(ing.quantity, ing.unit, base)! * f;
    }
  }
  return _finishNeeds(needs.values.toList());
}

/// Ajoute les stocks minimum aux besoins : recettes + minimum à garder.
List<Need> addMinStock(List<Need> needs, List<Product> products, List<Batch> batches, {DateTime? today}) {
  final list = List.of(needs);
  for (final p in products) {
    final min = p.minQty;
    if (min == null || min <= 0) continue;
    final base = baseUnit(p.unit);
    var n = list.where((x) => x.product?.id == p.id && x.unit == base).firstOrNull;
    if (n == null) {
      n = Need(name: p.name, unit: base, product: p, available: availableQuantity(p, batches, base, today: today));
      list.add(n);
    }
    n.needed += convert(min, p.unit, base)!;
    n.min = true;
  }
  return _finishNeeds(list);
}

/// Produits sous leur stock minimum.
List<Product> belowMinimum(Iterable<Product> products, List<Batch> batches, {DateTime? today}) => products
    .where((p) =>
        (p.minQty ?? 0) > 0 && availableQuantity(p, batches, p.unit, today: today) + 1e-9 < p.minQty!)
    .toList();

// ---------------------------------------------------------------------------
// Calories
// ---------------------------------------------------------------------------

/// Calories d'une quantité d'un produit (null si inconnu).
double? kcalOf(Product? p, double q, String unit) {
  if (p == null || p.kcal100 == null) return null;
  final base = baseUnit(unit);
  double amount;
  if (base == 'pièce') {
    final pq = p.packQty, pu = p.packUnit;
    if (pq == null || pq <= 0 || pu == null || baseUnit(pu) == 'pièce') return null;
    amount = q * convert(pq, pu, baseUnit(pu))!;
  } else {
    amount = convert(q, unit, base)!;
  }
  return amount * p.kcal100! / 100;
}

class RecipeKcal {
  final double total;
  final double? perPerson;
  final int unknown; // ingrédients sans calories connues
  RecipeKcal(this.total, this.perPerson, this.unknown);
}

/// Calories d'une recette pour [people] personnes (défaut : ses portions).
RecipeKcal recipeKcal(Recipe r, List<Product> products, {int? people}) {
  final f = portionFactor(r, people);
  var total = 0.0;
  var unknown = 0;
  for (final ing in r.ingredients) {
    final k = kcalOf(matchProduct(ing, products), ing.quantity * f, ing.unit);
    if (k == null) {
      unknown++;
    } else {
      total += k;
    }
  }
  final persons = (people != null && people > 0) ? people : (r.servings ?? 0);
  return RecipeKcal(total, persons > 0 ? total / persons : null, unknown);
}

// ---------------------------------------------------------------------------
// Liste de courses
// ---------------------------------------------------------------------------

/// Recalcule la liste de courses : garde les articles ajoutés à la main et
/// ceux déjà cochés, remplace les lignes automatiques par les manques actuels
/// (recettes prévues + stocks minimum, quantités cumulées).
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
      why: n.fromPlan && n.min ? 'both' : (n.min ? 'min' : 'plan'),
    ));
  }
  return [...added, ...kept];
}

// ---------------------------------------------------------------------------
// Emballage et quantité proposée au scan
// ---------------------------------------------------------------------------

class Pack {
  final int count;
  final double each;
  final String unit;
  const Pack(this.count, this.each, this.unit);
}

/// « 4 x 125 g » → Pack(4, 125, g) ; « 400 g » → Pack(1, 400, g).
Pack? parsePack(String? s) {
  if (s == null) return null;
  final t = s.toLowerCase().replaceAll(',', '.');
  final m = RegExp(r'(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b').firstMatch(t);
  if (m == null) return null;
  var each = double.parse(m.group(2)!);
  var u = m.group(3)!;
  if (u == 'cl') {
    each *= 10;
    u = 'ml';
  }
  if (u == 'l') u = 'L';
  return Pack(m.group(1) == null ? 1 : int.parse(m.group(1)!), each, u);
}

/// Quantité proposée : un lot de 4 yaourts → 4 pièces ; un pot de 400 g → 400 g.
(double, String) suggestQuantity(Pack? pack) {
  if (pack == null) return (1, 'pièce');
  if (pack.count > 1) return (pack.count.toDouble(), 'pièce');
  return (pack.each, pack.unit);
}

// ---------------------------------------------------------------------------
// Dates lues sur une photo (jamais devinées)
// ---------------------------------------------------------------------------

class FoundDate {
  final DateTime date;
  final String text;
  final bool monthOnly; // « fin 06/2027 » → dernier jour du mois
  FoundDate(this.date, this.text, this.monthOnly);
}

const _monthWords = {
  'jan': 1, 'janv': 1, 'fev': 2, 'fevr': 2, 'feb': 2, 'mar': 3, 'mars': 3, 'avr': 4, 'apr': 4,
  'mai': 5, 'may': 5, 'jun': 6, 'juin': 6, 'jul': 7, 'juil': 7, 'aou': 8, 'aout': 8, 'aug': 8,
  'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

String _stripAccents(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûü';
  const to = 'aaaaaaceeeeiiiinooooouuuu';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Cherche des dates COMPLÈTES dans un texte lu sur une photo :
/// 12/05/2027, 12.05.27, 12-05-2027, 12 05 27, 12 MAI 2027, et « 05/2027 »
/// (dernier jour du mois). Garde seulement les dates entre 2 ans avant et
/// 6 ans après aujourd'hui. Ne devine jamais un chiffre manquant.
List<FoundDate> findDates(String text, {DateTime? today}) {
  final t = _stripAccents(text.toLowerCase());
  final now = dateOnly(today ?? DateTime.now());
  final min = now.subtract(const Duration(days: 730));
  final max = now.add(const Duration(days: 6 * 366));
  final found = <FoundDate>[];
  final seen = <String>{};
  void add(int y, int m, int d, String raw, bool monthOnly) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > DateTime(y, m + 1, 0).day) return;
    final date = DateTime(y, m, d);
    if (date.isBefore(min) || date.isAfter(max)) return;
    if (!seen.add(dateToKey(date))) return;
    found.add(FoundDate(date, raw.trim(), monthOnly));
  }

  for (final m in RegExp(r'(^|[^\d])(\d{1,2})\s?[/.\-\s]\s?(\d{1,2})\s?[/.\-\s]\s?(\d{4}|\d{2})(?!\d)').allMatches(t)) {
    add(int.parse(m.group(4)!), int.parse(m.group(3)!), int.parse(m.group(2)!), m.group(0)!, false);
  }
  for (final m in RegExp(r'(^|[^\d])(\d{1,2})\s*([a-z]{3,5})\.?\s*(\d{4}|\d{2})(?!\d)').allMatches(t)) {
    final mo = _monthWords[m.group(3)];
    if (mo != null) add(int.parse(m.group(4)!), mo, int.parse(m.group(2)!), m.group(0)!, false);
  }
  if (found.isEmpty) {
    for (final m in RegExp(r'(^|[^\d/.\-])(\d{1,2})\s?[/.\-]\s?(\d{4})(?![\d/.\-])').allMatches(t)) {
      final y = int.parse(m.group(3)!), mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12) add(y, mo, DateTime(y, mo + 1, 0).day, m.group(0)!, true);
    }
  }
  return found;
}
