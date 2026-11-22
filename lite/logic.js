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
  function sortFefo(batches) {
    return batches.slice().sort(function (a, b) {
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
      if (daysUntil(b.exp, today) < 0) return;
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
            available: p ? availableQuantity(p, batches, base, today) : 0
          };
          order.push(key);
        }
        needs[key].needed += convert(ing.qty, ing.unit, base);
      });
    });
    var list = order.map(function (k) {
      var n = needs[k];
      n.missing = n.needed - n.available > 1e-9 ? n.needed - n.available : 0;
      return n;
    });
    list.sort(function (a, b) {
      if ((a.missing > 0) !== (b.missing > 0)) return a.missing > 0 ? -1 : 1;
      var x = normalizeName(a.name), y = normalizeName(b.name);
      return x < y ? -1 : x > y ? 1 : 0;
    });
    return list;
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
        name: n.name, qty: h[0], unit: h[1], checked: false, auto: true
      });
    });
    return added.concat(kept);
  }

  // ---------------------------------------------------------------- Open Food Facts
  function mapOffCategory(tags) {
    function has(keys) {
      return tags.some(function (t) { return keys.some(function (k) { return t.indexOf(k) >= 0; }); });
    }
    if (has(['frozen'])) return 'Surgelé';
    if (has(['beverages', 'drinks', 'waters', 'juices', 'sodas', 'wines', 'beers'])) return 'Boissons';
    if (has(['canned'])) return 'Conserves';
    if (has(['dairies', 'dairy', 'yogurts', 'cheeses', 'meats', 'fresh', 'eggs', 'fishes',
      'butters', 'creams', 'hams', 'sausages', 'refrigerated'])) return 'Frais';
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

  var Logic = {
    UNITS: UNITS, DEFAULT_CATEGORIES: DEFAULT_CATEGORIES,
    baseUnit: baseUnit, convert: convert, humanize: humanize, formatNumber: formatNumber,
    formatQty: formatQty, parseNumber: parseNumber, normalizeName: normalizeName,
    dateKey: dateKey, todayKey: todayKey, keyToDate: keyToDate, addDays: addDays,
    daysUntil: daysUntil, expiryStatus: expiryStatus, expiryLabel: expiryLabel,
    sortFefo: sortFefo, consumeFefo: consumeFefo, matchProduct: matchProduct,
    availableQuantity: availableQuantity, computeNeeds: computeNeeds,
    regenerateShopping: regenerateShopping, mapOffCategory: mapOffCategory,
    parseOffQuantity: parseOffQuantity
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = Logic;
  else root.Logic = Logic;
})(this);
