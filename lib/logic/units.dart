// Unités et conversions (g ↔ kg, ml ↔ L).

const units = ['pièce', 'g', 'kg', 'ml', 'L'];

/// Unité de base pour comparer des quantités : g, ml ou pièce.
String baseUnit(String unit) {
  switch (unit) {
    case 'g':
    case 'kg':
      return 'g';
    case 'ml':
    case 'L':
      return 'ml';
    default:
      return 'pièce';
  }
}

double _factor(String unit) => (unit == 'kg' || unit == 'L') ? 1000 : 1;

/// Convertit une quantité d'une unité à une autre ; null si incompatibles.
double? convert(double qty, String from, String to) {
  if (baseUnit(from) != baseUnit(to)) return null;
  return qty * _factor(from) / _factor(to);
}

/// Choisit une unité lisible pour une quantité exprimée en unité de base
/// (ex. 1500 g → 1,5 kg).
(double, String) humanize(double qty, String base) {
  if (base == 'g' && qty >= 1000) return (qty / 1000, 'kg');
  if (base == 'ml' && qty >= 1000) return (qty / 1000, 'L');
  return (qty, base);
}

/// Affiche un nombre « à la française » sans zéros inutiles : 1,5 / 2 / 0,25.
String formatNumber(double v) {
  final rounded = (v * 1000).round() / 1000;
  var s = rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

String formatQty(double qty, String unit) {
  final n = formatNumber(qty);
  if (unit == 'pièce') return qty > 1 ? '$n pièces' : '$n pièce';
  return '$n $unit';
}

/// Lit un nombre saisi par l'utilisateur (accepte la virgule).
double? parseNumber(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Normalise un nom pour comparer : minuscules, sans accents, sans pluriel.
String normalizeName(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buf = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    if (i < 0) {
      buf.write(ch);
    } else if (ch == 'œ') {
      buf.write('oe');
    } else if (ch == 'æ') {
      buf.write('ae');
    } else {
      buf.write(to[i]);
    }
  }
  return buf
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => (w.length > 3 && (w.endsWith('s') || w.endsWith('x')))
          ? w.substring(0, w.length - 1)
          : w)
      .join(' ');
}
