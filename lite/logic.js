/*
 * Stock Alimentaire — logique « métier » (sans interface).
 * Compatible Safari 12 (iPad iOS 12) : pas de ?. ni ??, pas de replaceAll.
 * Utilisable dans le navigateur (window.Logic) et dans Node (tests).
 */
(function (root) {
  'use strict';

  var UNITS = ['pièce', 'g', 'kg', 'ml', 'L'];
  var DEFAULT_CATEGORIES = ['Frais', 'Surgelé', 'Épicerie', 'Conserves', 'Boissons', 'Autre'];

  // ---------------------------------------------------------------- unités
  function baseUnit(u) {
    if (u === 'g' || u === 'kg') return 'g';
    if (u === 'ml' || u === 'L') return 'ml';
    return 'pièce';
  }
  function factor(u) { return (u === 'kg' || u === 'L') ? 1000 : 1; }

  /** Convertit une quantité ; null si les unités sont incompatibles. */
  function convert(q, from, to) {
    if (baseUnit(from) !== baseUnit(to)) return null;
    return q * factor(from) / factor(to);
  }

  /** 1500 g → [1.5, 'kg'] */
  function humanize(q, base) {
    if (base === 'g' && q >= 1000) return [q / 1000, 'kg'];
    if (base === 'ml' && q >= 1000) return [q / 1000, 'L'];
    return [q, base];
  }

  /** 1,5 / 2 / 0,25 */
  function formatNumber(v) {
    var r = Math.round(v * 1000) / 1000;
    var s = r === Math.round(r) ? String(Math.round(r)) : r.toFixed(3).replace(/0+$/, '');
    return s.replace('.', ',');
  }

  function formatQty(q, u) {
    var n = formatNumber(q);
    if (u === 'pièce') return n + (q > 1 ? ' pièces' : ' pièce');
    return n + ' ' + u;
  }

  /** Lit un nombre saisi (accepte la virgule). null si invalide. */
  function parseNumber(s) {
    if (s === null || s === undefined) return null;
    var t = String(s).trim().replace(',', '.');
    if (t === '') return null;
    var v = Number(t);
    return isFinite(v) ? v : null;
  }

  /** Minuscules, sans accents, sans pluriel : « Œufs » → « oeuf ». */
  function normalizeName(s) {
    var t = String(s || '').toLowerCase().replace(/œ/g, 'oe').replace(/æ/g, 'ae');
    if (t.normalize) t = t.normalize('NFD').replace(/[̀-ͯ]/g, '');
    return t.replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(function (w) { return w; })
      .map(function (w) {
        var last = w.charAt(w.length - 1);
        return (w.length > 3 && (last === 's' || last === 'x')) ? w.slice(0, -1) : w;
      }).join(' ');
  }

  // ---------------------------------------------------------------- dates
  // Les dates « jour » sont des textes AAAA-MM-JJ (pas de souci de fuseau).
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function dateKey(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function todayKey() { return dateKey(new Date()); }
  function keyToUtc(k) {
    var p = k.split('-');
    return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  }
  function keyToDate(k) {
    var p = k.split('-');
    return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  }
  function addDays(k, n) {
    var d = keyToDate(k);
    d.setDate(d.getDate() + n);
    return dateKey(d);
  }

  /** Jours restants (0 = aujourd'hui, négatif = périmé). */
  function daysUntil(expKey, today) {
    return Math.round((keyToUtc(expKey) - keyToUtc(today || todayKey())) / 86400000);
  }

  /** 'ok' (vert), 'soon' (orange), 'expired' (rouge). */
  function expiryStatus(days, alertDays) {
    if (alertDays === undefined) alertDays = 3;
    if (days < 0) return 'expired';
    if (days <= alertDays) return 'soon';
    return 'ok';
  }

  function expiryLabel(days) {
    if (days < -1) return 'périmé depuis ' + (-days) + ' jours';
    if (days === -1) return 'périmé depuis hier';
    if (days === 0) return "périme aujourd'hui";
    if (days === 1) return 'périme demain';
    return 'dans ' + days + ' jours';
  }

  // ---------------------------------------------------------------- FEFO
  /** Lots du plus urgent au moins urgent ; les lots congelés passent en dernier. */
  function sortFefo(batches) {
    return batches.slice().sort(function (a, b) {
      if (!!a.frozen !== !!b.frozen) return a.frozen ? 1 : -1;
      if (a.exp !== b.exp) return a.exp < b.exp ? -1 : 1;
      return (a.added || '') < (b.added || '') ? -1 : 1;
    });
  }

  /** Prend d'abord dans le lot qui périme le plus tôt.
   *  Renvoie { newQuantities: {idLot: qté restante (0 = à supprimer)}, missing } */
  function consumeFefo(batches, qty) {
    var remaining = qty;
    var result = {};
    var lots = sortFefo(batches);
    for (var i = 0; i < lots.length && remaining > 1e-9; i++) {
      var b = lots[i];
      var take = Math.min(b.qty, remaining);
      var left = b.qty - take;
      result[b.id] = left < 1e-9 ? 0 : left;
      remaining -= take;
    }
    return { newQuantities: result, missing: remaining < 1e-9 ? 0 : remaining };
  }

  // ---------------------------------------------------------------- recettes
  /** Produit du stock correspondant à un ingrédient (lien, nom exact, début de nom). */
  function matchProduct(ing, products) {
    var i;
    if (ing.productId) {
      for (i = 0; i < products.length; i++) if (products[i].id === ing.productId) return products[i];
    }
    var n = normalizeName(ing.name);
    if (!n) return null;
    for (i = 0; i < products.length; i++) if (normalizeName(products[i].name) === n) return products[i];
    for (i = 0; i < products.length; i++) {
      if (normalizeName(products[i].name).indexOf(n + ' ') === 0) return products[i];
    }
    return null;
  }

  /** Quantité non périmée d'un produit, exprimée dans `unit`. */
  function availableQuantity(p, batches, unit, today) {
    var total = 0;
    batches.forEach(function (b) {
      if (b.productId !== p.id) return;
      if (!b.frozen && daysUntil(b.exp, today) < 0) return;
      total += convert(b.qty, p.unit, unit) || 0;
    });
    return total;
  }

  /** Cumule les ingrédients des recettes prévues (non faites) et compare au stock.
   *  Renvoie [{name, unit (de base), product, needed, available, missing}] manquants d'abord. */
  function computeNeeds(plan, recipesById, products, batches, today) {
    var needs = {};
    var order = [];
    plan.forEach(function (entry) {
      if (entry.done) return;
      var r = recipesById[entry.recipeId];
      if (!r) return;
      var f = portionFactor(r, entry.people);
      r.ingredients.forEach(function (ing) {
        var p = matchProduct(ing, products);
        var base = baseUnit(ing.unit);
        var key = (p ? p.id : normalizeName(ing.name)) + '|' + base;
        if (!needs[key]) {
          needs[key] = {
            name: p ? p.name : String(ing.name).trim(),
            unit: base,
            product: p,
            needed: 0,
            available: p ? availableQuantity(p, batches, base, today) : 0,
            fromPlan: true
          };
          order.push(key);
        }
        needs[key].needed += convert(ing.qty, ing.unit, base) * f;
      });
    });
    return finishNeeds(order.map(function (k) { return needs[k]; }));
  }

  /** Calcule ce qui manque et trie (manquants d'abord, puis par nom). */
  function finishNeeds(list) {
    list.forEach(function (n) {
      n.missing = n.needed - n.available > 1e-9 ? n.needed - n.available : 0;
    });
    list.sort(function (a, b) {
      if ((a.missing > 0) !== (b.missing > 0)) return a.missing > 0 ? -1 : 1;
      var x = normalizeName(a.name), y = normalizeName(b.name);
      return x < y ? -1 : x > y ? 1 : 0;
    });
    return list;
  }

  /** Ajoute les « stocks minimum » (p.minQty, dans l'unité du produit) aux besoins :
   *  ce qu'il faut pour les recettes PLUS le minimum à garder. */
  function addMinStock(needs, products, batches, today) {
    var list = needs.slice();
    products.forEach(function (p) {
      if (!(p.minQty > 0)) return;
      var base = baseUnit(p.unit);
      var min = convert(p.minQty, p.unit, base);
      var n = null;
      for (var i = 0; i < list.length; i++) {
        if (list[i].product && list[i].product.id === p.id && list[i].unit === base) { n = list[i]; break; }
      }
      if (!n) {
        n = { name: p.name, unit: base, product: p, needed: 0, available: availableQuantity(p, batches, base, today) };
        list.push(n);
      }
      n.needed += min;
      n.min = true;
    });
    return finishNeeds(list);
  }

  /** Produits sous leur stock minimum. */
  function belowMinimum(products, batches, today) {
    return products.filter(function (p) {
      return p.minQty > 0 && availableQuantity(p, batches, p.unit, today) + 1e-9 < p.minQty;
    });
  }

  /** Liste de courses : garde le manuel et le coché, remplace les lignes
   *  automatiques par les manques actuels (quantités cumulées). */
  function regenerateShopping(current, needs, newId) {
    var kept = current.filter(function (i) { return !i.auto || i.checked; });
    var keptNames = {};
    kept.forEach(function (i) { if (i.auto) keptNames[normalizeName(i.name)] = true; });
    var previous = {};
    current.forEach(function (i) {
      if (i.auto && !i.checked) previous[normalizeName(i.name) + '|' + i.unit] = i.id;
    });
    var added = [];
    needs.forEach(function (n) {
      if (!(n.missing > 0)) return;
      if (keptNames[normalizeName(n.name)]) return;
      var h = humanize(n.missing, n.unit);
      added.push({
        id: previous[normalizeName(n.name) + '|' + h[1]] || newId(),
        name: n.name, qty: h[0], unit: h[1], checked: false, auto: true,
        why: n.fromPlan && n.min ? 'both' : (n.min ? 'min' : 'plan')
      });
    });
    return added.concat(kept);
  }

  // ---------------------------------------------------------------- Open Food Facts
  // Étiquettes trop générales ignorées (« plant-based-foods-and-BEVERAGES »
  // classait des pâtes dans Boissons). Mêmes règles que tools/build_products.py.
  var IGNORED_TAGS = ['en:plant-based-foods-and-beverages', 'en:plant-based-foods',
    'en:beverages-and-beverages-preparations'];

  function mapOffCategory(allTags) {
    // aussi « fruit-based-foods-and-beverages », « vegetable-based-foods-and-beverages »…
    var tags = allTags.filter(function (t) { return IGNORED_TAGS.indexOf(t) < 0 && t.indexOf('foods-and-beverages') < 0; });
    function has(keys) {
      return tags.some(function (t) { return keys.some(function (k) { return t.indexOf(k) >= 0; }); });
    }
    if (has(['frozen'])) return 'Surgelé';
    if (has(['beverages', 'drinks', 'waters', 'juices', 'sodas', 'wines', 'beers', 'ciders',
      'spirits', 'alcoholic', 'nectars', 'plant-milks'])) return 'Boissons';
    if (has(['canned'])) return 'Conserves';
    if (has(['dairies', 'dairy', 'yogurts', 'cheeses', 'meats', 'fresh', 'eggs', 'fishes',
      'butters', 'creams', 'hams', 'sausages', 'refrigerated', 'chilled', 'charcuteries',
      'poultries', 'seafood', 'fermented-milk'])) return 'Frais';
    if (!tags.length) return 'Autre';
    return 'Épicerie';
  }

  /** « 500 g », « 4 x 125 g », « 33 cl » → [qté, unité] ou null */
  function parseOffQuantity(s) {
    if (!s) return null;
    var t = String(s).toLowerCase().replace(/,/g, '.');
    var m = /(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b/.exec(t);
    if (!m) return null;
    var count = m[1] ? Number(m[1]) : 1;
    var v = Number(m[2]) * count;
    var u = m[3];
    if (u === 'cl') { v *= 10; u = 'ml'; }
    if (u === 'l') u = 'L';
    return [v, u];
  }

  /** Contenance d'un emballage : « 4 x 125 g » → {count: 4, each: 125, unit: 'g'},
   *  « 400 g » → {count: 1, each: 400, unit: 'g'}. null si illisible. */
  function parsePack(s) {
    if (!s) return null;
    var t = String(s).toLowerCase().replace(/,/g, '.');
    var m = /(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b/.exec(t);
    if (!m) return null;
    var each = Number(m[2]);
    var u = m[3];
    if (u === 'cl') { each *= 10; u = 'ml'; }
    if (u === 'l') u = 'L';
    return { count: m[1] ? Number(m[1]) : 1, each: each, unit: u };
  }

  /** Quantité proposée au scan : un lot de 4 yaourts → 4 pièces ; un pot de 400 g → 400 g. */
  function suggestQuantity(pack) {
    if (!pack) return { qty: 1, unit: 'pièce' };
    if (pack.count > 1) return { qty: pack.count, unit: 'pièce' };
    return { qty: pack.each, unit: pack.unit };
  }

  /** Facteur des portions : recette pour 4, cuisinée pour 2 → 0,5. */
  function portionFactor(recipe, people) {
    var s = recipe && recipe.servings > 0 ? recipe.servings : 0;
    return (s && people > 0) ? people / s : 1;
  }

  /** Calories d'une quantité d'un produit (null si inconnu).
   *  p.kcal100 = kcal pour 100 g ou 100 ml ; p.packQty/p.packUnit = poids d'une pièce. */
  function kcalOf(p, q, unit) {
    if (!p || typeof p.kcal100 !== 'number') return null;
    var base = baseUnit(unit);
    var amount;
    if (base === 'pièce') {
      if (!(p.packQty > 0) || baseUnit(p.packUnit || 'pièce') === 'pièce') return null;
      amount = q * convert(p.packQty, p.packUnit, baseUnit(p.packUnit));
    } else {
      amount = convert(q, unit, base);
    }
    return amount * p.kcal100 / 100;
  }

  /** Calories d'une recette pour `people` personnes (défaut : ses portions). */
  function recipeKcal(recipe, products, people) {
    var f = portionFactor(recipe, people);
    var total = 0, unknown = 0;
    recipe.ingredients.forEach(function (ing) {
      var k = kcalOf(matchProduct(ing, products), ing.qty * f, ing.unit);
      if (k === null) unknown++;
      else total += k;
    });
    var persons = people > 0 ? people : (recipe.servings > 0 ? recipe.servings : 0);
    return { total: total, perPerson: persons ? total / persons : null, unknown: unknown };
  }

  // ---------------------------------------------------------------- dates lues sur photo
  var MONTH_WORDS = {
    jan: 1, janv: 1, fev: 2, fevr: 2, feb: 2, mar: 3, mars: 3, avr: 4, apr: 4, mai: 5, may: 5,
    jun: 6, juin: 6, jul: 7, juil: 7, aou: 8, aout: 8, aug: 8, sep: 9, sept: 9, oct: 10,
    nov: 11, dec: 12
  };

  function validDate(y, m, d) {
    if (m < 1 || m > 12 || d < 1) return false;
    return d <= new Date(y, m, 0).getDate();
  }
  function fullYear(y) { return y < 100 ? 2000 + y : y; }

  /** Cherche des dates COMPLÈTES dans un texte lu sur une photo (jamais devinées) :
   *  12/05/2027, 12.05.27, 12-05-2027, 12 05 27, 12 MAI 2027, et « 05/2027 »
   *  (date limite au mois → dernier jour du mois, signalé par monthOnly).
   *  Ne garde que les dates entre 2 ans avant et 6 ans après aujourd'hui.
   *  Renvoie [{key: 'AAAA-MM-JJ', text, monthOnly}] sans doublon. */
  function findDates(text, today) {
    var t = String(text || '').toLowerCase();
    if (t.normalize) t = t.normalize('NFD').replace(/[̀-ͯ]/g, '');
    var now = today || todayKey();
    var min = addDays(now, -730), max = addDays(now, 6 * 366);
    var found = [];
    var seen = {};
    function add(y, m, d, raw, monthOnly) {
      y = fullYear(y);
      if (!validDate(y, m, d)) return;
      var key = y + '-' + pad(m) + '-' + pad(d);
      if (key < min || key > max || seen[key]) return;
      seen[key] = true;
      found.push({ key: key, text: raw.trim(), monthOnly: !!monthOnly });
    }
    var m;
    // jour / mois / année (séparateurs / . - ou espace)
    var reNum = /(^|[^\d])(\d{1,2})\s?[\/.\-\s]\s?(\d{1,2})\s?[\/.\-\s]\s?(\d{4}|\d{2})(?!\d)/g;
    while ((m = reNum.exec(t)) !== null) add(Number(m[4]), Number(m[3]), Number(m[2]), m[0], false);
    // jour + mois en lettres + année
    var reWord = /(^|[^\d])(\d{1,2})\s*([a-z]{3,5})\.?\s*(\d{4}|\d{2})(?!\d)/g;
    while ((m = reWord.exec(t)) !== null) {
      var mo = MONTH_WORDS[m[3]];
      if (mo) add(Number(m[4]), mo, Number(m[2]), m[0], false);
    }
    // mois / année seuls (ex. « à consommer de préférence avant fin 06/2027 »)
    if (!found.length) {
      var reMonth = /(^|[^\d\/.\-])(\d{1,2})\s?[\/.\-]\s?(\d{4})(?![\d\/.\-])/g;
      while ((m = reMonth.exec(t)) !== null) {
        var y = Number(m[3]), mm = Number(m[2]);
        if (mm >= 1 && mm <= 12) add(y, mm, new Date(y, mm, 0).getDate(), m[0], true);
      }
    }
    return found;
  }

  var Logic = {
    UNITS: UNITS, DEFAULT_CATEGORIES: DEFAULT_CATEGORIES,
    baseUnit: baseUnit, convert: convert, humanize: humanize, formatNumber: formatNumber,
    formatQty: formatQty, parseNumber: parseNumber, normalizeName: normalizeName,
    dateKey: dateKey, todayKey: todayKey, keyToDate: keyToDate, addDays: addDays,
    daysUntil: daysUntil, expiryStatus: expiryStatus, expiryLabel: expiryLabel,
    sortFefo: sortFefo, consumeFefo: consumeFefo, matchProduct: matchProduct,
    availableQuantity: availableQuantity, computeNeeds: computeNeeds,
    regenerateShopping: regenerateShopping, mapOffCategory: mapOffCategory,
    parseOffQuantity: parseOffQuantity, parsePack: parsePack, suggestQuantity: suggestQuantity,
    portionFactor: portionFactor, kcalOf: kcalOf, recipeKcal: recipeKcal,
    addMinStock: addMinStock, belowMinimum: belowMinimum, findDates: findDates
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = Logic;
  else root.Logic = Logic;
})(this);
