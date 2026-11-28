// Tests de la logique : `node --test lite/test/`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('../logic.js');

const today = '2026-11-22';

test('jours restants et couleurs', () => {
  assert.equal(L.daysUntil('2026-11-22', today), 0);
  assert.equal(L.daysUntil('2026-11-25', today), 3);
  assert.equal(L.daysUntil('2026-11-21', today), -1);
  assert.equal(L.daysUntil('2026-03-30', '2026-03-28'), 2); // changement d'heure
  assert.equal(L.expiryStatus(4), 'ok');
  assert.equal(L.expiryStatus(3), 'soon');
  assert.equal(L.expiryStatus(-1), 'expired');
  assert.equal(L.expiryStatus(5, 5), 'soon');
  assert.equal(L.addDays('2026-12-30', 3), '2027-01-02');
});

test('FEFO : le lot qui périme le plus tôt part en premier', () => {
  const lots = [
    { id: 'b', productId: 'p', qty: 2, exp: '2026-12-07' },
    { id: 'a', productId: 'p', qty: 2, exp: '2026-12-02' },
  ];
  assert.deepEqual(L.consumeFefo(lots, 1).newQuantities, { a: 1 });
  assert.deepEqual(L.consumeFefo(lots, 3).newQuantities, { a: 0, b: 1 });
  const r = L.consumeFefo(lots, 5.5);
  assert.deepEqual(r.newQuantities, { a: 0, b: 0 });
  assert.equal(r.missing, 1.5);
});

test('unités, nombres et noms', () => {
  assert.equal(L.convert(500, 'g', 'kg'), 0.5);
  assert.equal(L.convert(1.5, 'L', 'ml'), 1500);
  assert.equal(L.convert(1, 'pièce', 'g'), null);
  assert.deepEqual(L.humanize(1500, 'g'), [1.5, 'kg']);
  assert.equal(L.formatQty(1.5, 'kg'), '1,5 kg');
  assert.equal(L.formatQty(2, 'pièce'), '2 pièces');
  assert.equal(L.parseNumber('0,25'), 0.25);
  assert.equal(L.parseNumber('abc'), null);
  assert.equal(L.normalizeName('Œufs'), 'oeuf');
  assert.equal(L.normalizeName('  Pâtes  complètes '), 'pate complete');
});

test('Open Food Facts : quantités et catégories', () => {
  assert.deepEqual(L.parseOffQuantity('500 g'), [500, 'g']);
  assert.deepEqual(L.parseOffQuantity('4 x 125 g'), [500, 'g']);
  assert.deepEqual(L.parseOffQuantity('1,5 L'), [1.5, 'L']);
  assert.deepEqual(L.parseOffQuantity('33 cl'), [330, 'ml']);
  assert.equal(L.parseOffQuantity('6 pots'), null);
  assert.equal(L.mapOffCategory(['en:frozen-foods']), 'Surgelé');
  assert.equal(L.mapOffCategory(['en:dairies', 'en:yogurts']), 'Frais');
  assert.equal(L.mapOffCategory(['en:spreads']), 'Épicerie');
  assert.equal(L.mapOffCategory([]), 'Autre');
});

test('besoins des recettes et liste de courses', () => {
  const products = [
    { id: 'oeufs', name: 'Oeufs frais', unit: 'pièce' },
    { id: 'farine', name: 'Farine T55', unit: 'kg' },
    { id: 'lait', name: 'Lait demi-écrémé', unit: 'L' },
  ];
  const batches = [
    { id: '1', productId: 'oeufs', qty: 4, exp: '2026-12-01' },
    { id: '2', productId: 'oeufs', qty: 6, exp: '2026-11-01' }, // périmés : ignorés
    { id: '3', productId: 'farine', qty: 1, exp: '2027-06-01' },
    { id: '4', productId: 'lait', qty: 0.5, exp: '2026-11-30' },
  ];
  const recipes = {
    crepes: { id: 'crepes', name: 'Crêpes', ingredients: [
      { name: 'Oeufs frais', qty: 3, unit: 'pièce', productId: 'oeufs' },
      { name: 'farine', qty: 250, unit: 'g' },
      { name: 'Lait', qty: 500, unit: 'ml' },
    ] },
    gateau: { id: 'gateau', name: 'Gâteau', ingredients: [
      { name: 'Oeufs frais', qty: 3, unit: 'pièce', productId: 'oeufs' },
      { name: 'Sucre', qty: 100, unit: 'g' },
    ] },
  };
  const plan = [{ id: 'e1', recipeId: 'crepes' }, { id: 'e2', recipeId: 'gateau' }];
  const needs = L.computeNeeds(plan, recipes, products, batches, today);
  const by = {};
  needs.forEach((n) => { by[n.name] = n; });
  assert.equal(by['Oeufs frais'].needed, 6);
  assert.equal(by['Oeufs frais'].available, 4);
  assert.equal(by['Oeufs frais'].missing, 2);
  assert.equal(by['Farine T55'].needed, 250);
  assert.equal(by['Farine T55'].missing, 0);
  assert.equal(by['Lait demi-écrémé'].missing, 0);
  assert.equal(by['Sucre'].missing, 100);
  assert.ok(needs[0].missing > 0 && needs[1].missing > 0);
  assert.equal(L.computeNeeds([{ recipeId: 'gateau', done: true }], recipes, products, batches, today).length, 0);

  let n = 0;
  const list = L.regenerateShopping([
    { id: 'm', name: 'Pain', auto: false, checked: false },
    { id: 'old', name: 'Beurre', auto: true, checked: false },
    { id: 'c', name: 'Sucre', auto: true, checked: true },
  ], needs, () => 'new' + (n++));
  const names = list.map((i) => i.name);
  assert.ok(names.includes('Pain'));
  assert.ok(!names.includes('Beurre'));
  assert.equal(names.filter((x) => x === 'Sucre').length, 1);
  const oeufs = list.find((i) => i.name === 'Oeufs frais');
  assert.equal(oeufs.qty, 2);
  assert.equal(oeufs.auto, true);
});

test('catégories : « plant-based-foods-and-beverages » ne veut pas dire Boissons', () => {
  assert.equal(L.mapOffCategory(['en:plant-based-foods-and-beverages', 'en:plant-based-foods', 'en:pastas']), 'Épicerie');
  assert.equal(L.mapOffCategory(['en:plant-based-foods-and-beverages', 'en:beverages', 'en:plant-milks']), 'Boissons');
  assert.equal(L.mapOffCategory(['en:charcuteries', 'en:hams']), 'Frais');
  assert.equal(L.mapOffCategory(['en:plant-based-foods-and-beverages', 'en:fruit-based-foods-and-beverages', 'en:spreads', 'en:jams']), 'Épicerie');
  assert.equal(L.mapOffCategory(['en:plant-based-foods-and-beverages', 'en:vegetable-based-foods-and-beverages', 'en:vegetables', 'en:artichokes']), 'Épicerie');
});

test('quantité proposée au scan', () => {
  assert.deepEqual(L.parsePack('4 x 125 g'), { count: 4, each: 125, unit: 'g' });
  assert.deepEqual(L.suggestQuantity(L.parsePack('4 x 125 g')), { qty: 4, unit: 'pièce' });
  assert.deepEqual(L.suggestQuantity(L.parsePack('400 g')), { qty: 400, unit: 'g' });
  assert.deepEqual(L.suggestQuantity(L.parsePack('1,5 L')), { qty: 1.5, unit: 'L' });
  assert.deepEqual(L.suggestQuantity(null), { qty: 1, unit: 'pièce' });
});

test('calories : produits et recettes, par personne', () => {
  const nutella = { id: 'n', name: 'Nutella', unit: 'g', kcal100: 539 };
  const yaourt = { id: 'y', name: 'Yaourt', unit: 'pièce', kcal100: 60, packQty: 125, packUnit: 'g' };
  const lait = { id: 'l', name: 'Lait', unit: 'L', kcal100: 46 };
  assert.equal(L.kcalOf(nutella, 15, 'g'), 539 * 0.15);
  assert.equal(L.kcalOf(yaourt, 2, 'pièce'), 150);
  assert.equal(L.kcalOf(lait, 0.5, 'L'), 230);
  assert.equal(L.kcalOf({ id: 'x', unit: 'g' }, 100, 'g'), null);
  assert.equal(L.kcalOf({ id: 'x', unit: 'pièce', kcal100: 50 }, 1, 'pièce'), null); // poids inconnu
  const r = { id: 'r', name: 'Gâteau', servings: 4, ingredients: [
    { name: 'Yaourt', qty: 2, unit: 'pièce', productId: 'y' },
    { name: 'Lait', qty: 500, unit: 'ml' },
    { name: 'Sel', qty: 1, unit: 'g' },
  ] };
  const k = L.recipeKcal(r, [nutella, yaourt, lait]);
  assert.equal(k.total, 150 + 230);
  assert.equal(k.perPerson, 95);
  assert.equal(k.unknown, 1);
  const k8 = L.recipeKcal(r, [nutella, yaourt, lait], 8); // double
  assert.equal(k8.total, 760);
  assert.equal(k8.perPerson, 95);
});

test('portions : besoins proportionnels au nombre de personnes', () => {
  const recipes = { r: { id: 'r', name: 'Crêpes', servings: 4, ingredients: [{ name: 'Farine', qty: 250, unit: 'g' }] } };
  const n2 = L.computeNeeds([{ recipeId: 'r', people: 2 }], recipes, [], [], today);
  assert.equal(n2[0].needed, 125);
  const n8 = L.computeNeeds([{ recipeId: 'r', people: 8 }], recipes, [], [], today);
  assert.equal(n8[0].needed, 500);
  assert.equal(L.computeNeeds([{ recipeId: 'r' }], recipes, [], [], today)[0].needed, 250);
});

test('congelé : la date de péremption ne compte plus', () => {
  const p = { id: 'v', name: 'Viande', unit: 'g' };
  const lots = [
    { id: 'f', productId: 'v', qty: 500, exp: '2026-11-01', frozen: true },  // date dépassée mais congelé
    { id: 'a', productId: 'v', qty: 200, exp: '2026-11-25' },
  ];
  assert.equal(L.availableQuantity(p, lots, 'g', today), 700);
  assert.deepEqual(L.sortFefo(lots).map((b) => b.id), ['a', 'f']); // le frais d'abord
  assert.deepEqual(L.consumeFefo(lots, 300).newQuantities, { a: 0, f: 400 });
});

test('stock minimum : ajouté aux besoins et à la liste de courses', () => {
  const pates = { id: 'p', name: 'Pâtes', unit: 'pièce', minQty: 2 };
  const riz = { id: 'r', name: 'Riz', unit: 'kg', minQty: 1 };
  const batches = [{ id: '1', productId: 'p', qty: 1, exp: '2027-06-01' }, { id: '2', productId: 'r', qty: 2, exp: '2027-06-01' }];
  assert.deepEqual(L.belowMinimum([pates, riz], batches, today).map((p) => p.id), ['p']);
  const recipes = { c: { id: 'c', name: 'Carbo', ingredients: [{ name: 'Pâtes', qty: 1, unit: 'pièce', productId: 'p' }] } };
  const needs = L.addMinStock(L.computeNeeds([{ recipeId: 'c' }], recipes, [pates, riz], batches, today), [pates, riz], batches, today);
  const p = needs.find((n) => n.name === 'Pâtes');
  assert.equal(p.needed, 3); // 1 pour la recette + 2 de minimum
  assert.equal(p.missing, 2);
  assert.ok(!needs.find((n) => n.name === 'Riz').missing);
  const list = L.regenerateShopping([], needs, () => 'id');
  assert.equal(list.length, 1);
  assert.equal(list[0].why, 'both');
});

test('dates lues sur une photo : seulement si elles sont vraiment écrites', () => {
  const d = (txt) => L.findDates(txt, today).map((x) => x.key);
  assert.deepEqual(d('A consommer jusqu\'au 12/05/2027 L1234'), ['2027-05-12']);
  assert.deepEqual(d('DLC 03.12.26'), ['2026-12-03']);
  assert.deepEqual(d('à consommer de préférence avant le 15 MAI 2027'), ['2027-05-15']);
  assert.deepEqual(d('A consommer de préférence avant fin : 06/2027'), ['2027-06-30']);
  assert.equal(L.findDates('fin 06/2027', today)[0].monthOnly, true);
  assert.deepEqual(d('31/02/2027'), []);                  // date impossible
  assert.deepEqual(d('LOT 3017620422003 18:45'), []);     // pas de date
  assert.deepEqual(d('12/05/1998'), []);                   // trop ancienne
  assert.deepEqual(d('Le 01/12/2026 et le 05/12/2026'), ['2026-12-01', '2026-12-05']); // plusieurs : on demandera
});
