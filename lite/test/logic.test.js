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
