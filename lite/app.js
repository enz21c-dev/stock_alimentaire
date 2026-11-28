/*
 * Stock Alimentaire — version légère (HTML/JS), compatible iPad iOS 12.
 * Règles de compatibilité : pas de ?. ni ??, pas de replaceAll, pas de <dialog>.
 * Données enregistrées dans le navigateur (localStorage), rien sur un serveur.
 */
(function () {
  'use strict';
  var L = window.Logic;
  var STORAGE_KEY = 'stock_alimentaire_lite_v1';
  var BACKUP_FORMAT = 'stock_alimentaire_lite';
  var DEFAULT_LOCATIONS = ['Frigo', 'Congélateur', 'Placard', 'Cave'];

  // ======================================================================
  // Données
  // ======================================================================
  function emptyDb() {
    return {
      products: [], batches: [], recipes: [], plan: [], shopping: [],
      settings: {
        alertDays: 3, categories: L.DEFAULT_CATEGORIES.slice(), planByDay: true,
        useLocations: false, locations: DEFAULT_LOCATIONS.slice()
      }
    };
  }

  function normalizeDb(d) {
    var e = emptyDb();
    if (!d || typeof d !== 'object') return e;
    ['products', 'batches', 'recipes', 'plan', 'shopping'].forEach(function (k) {
      if (Array.isArray(d[k])) e[k] = d[k];
    });
    var s = d.settings || {};
    if (typeof s.alertDays === 'number') e.settings.alertDays = s.alertDays;
    if (Array.isArray(s.categories) && s.categories.length) e.settings.categories = s.categories;
    if (typeof s.planByDay === 'boolean') e.settings.planByDay = s.planByDay;
    if (typeof s.useLocations === 'boolean') e.settings.useLocations = s.useLocations;
    if (Array.isArray(s.locations) && s.locations.length) e.settings.locations = s.locations;
    return e;
  }

  function loadDb() {
    try {
      var s = localStorage.getItem(STORAGE_KEY);
      if (s) return normalizeDb(JSON.parse(s));
    } catch (e) { /* données illisibles : on repart de zéro */ }
    return emptyDb();
  }

  var db = loadDb();

  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(db));
      return true;
    } catch (e) {
      showToast("Mémoire pleine : retire des photos ou exporte une sauvegarde.");
      return false;
    }
  }

  var idCounter = 0;
  function newId() {
    idCounter++;
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 7) + idCounter;
  }

  function find(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
    return null;
  }
  function productById(id) { return find(db.products, id); }
  function recipeById(id) { return find(db.recipes, id); }
  function batchesOf(pid) { return L.sortFefo(db.batches.filter(function (b) { return b.productId === pid; })); }
  function totalOf(pid) { return batchesOf(pid).reduce(function (s, b) { return s + b.qty; }, 0); }
  function productsInStock() {
    var ids = {};
    db.batches.forEach(function (b) { ids[b.productId] = true; });
    return db.products.filter(function (p) { return ids[p.id]; });
  }
  function productByBarcode(code) {
    for (var i = 0; i < db.products.length; i++) if (db.products[i].barcode === code) return db.products[i];
    return null;
  }
  function productByName(name) {
    var n = L.normalizeName(name);
    if (!n) return null;
    for (var i = 0; i < db.products.length; i++) if (L.normalizeName(db.products[i].name) === n) return db.products[i];
    return null;
  }
  function expiringBatches() {
    var a = db.settings.alertDays;
    // Un lot congelé ne périme plus : pas d'alerte.
    return L.sortFefo(db.batches.filter(function (b) { return !b.frozen && L.daysUntil(b.exp) <= a; }));
  }

  /** Catégorie de l'appli correspondant à une catégorie par défaut (Open Food Facts),
   *  même si l'utilisateur l'a renommée (on suit sa position dans la liste). */
  function mapCategory(name) {
    var cats = db.settings.categories;
    if (cats.indexOf(name) >= 0) return name;
    var i = L.DEFAULT_CATEGORIES.indexOf(name);
    if (i >= 0 && i < cats.length && L.DEFAULT_CATEGORIES.indexOf(cats[i]) < 0) return cats[i];
    return cats.indexOf('Autre') >= 0 ? 'Autre' : cats[cats.length - 1];
  }
  function recipesMap() {
    var m = {};
    db.recipes.forEach(function (r) { m[r.id] = r; });
    return m;
  }
  function currentNeeds() {
    return L.computeNeeds(db.plan, recipesMap(), db.products, db.batches);
  }

  /** Garde la liste de courses à jour avec le planning et le stock. */
  function syncShopping() {
    var hasAuto = db.shopping.some(function (i) { return i.auto; });
    var hasMin = db.products.some(function (p) { return p.minQty > 0; });
    if (!db.plan.length && !hasAuto && !hasMin) return;
    var needs = L.addMinStock(currentNeeds(), db.products, db.batches);
    db.shopping = L.regenerateShopping(db.shopping, needs, newId);
  }

  /** Enregistre et redessine. */
  function commit() {
    syncShopping();
    save();
    render();
  }

  /** Comme commit, avec un bouton « Annuler » pendant quelques secondes. */
  function commitWithUndo(message, snapshot) {
    commit();
    showToast(message, function () {
      db = normalizeDb(JSON.parse(snapshot));
      commit();
      showToast('Annulé');
    });
  }
  function snapshot() { return JSON.stringify(db); }

  // ======================================================================
  // Outils d'affichage
  // ======================================================================
  function esc(s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function $(id) { return document.getElementById(id); }
  function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

  var MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  var MONTHS_LONG = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  var DAYS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
  function fmtDate(k) { var d = L.keyToDate(k); return d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear(); }
  function fmtDay(k) { var d = L.keyToDate(k); return cap(DAYS[d.getDay()] + ' ' + d.getDate() + ' ' + MONTHS_LONG[d.getMonth()]); }
  function qty(q, u) { return L.formatQty(q, u); }

  function status(exp) { return L.expiryStatus(L.daysUntil(exp), db.settings.alertDays); }
  function expiryTag(exp) {
    return '<span class="tag ' + status(exp) + '">' + esc(L.expiryLabel(L.daysUntil(exp))) + '</span>';
  }
  /** Étiquette d'un lot : congelé (pas de date), sinon date + « entamé ». */
  function lotTag(b) {
    if (b.frozen) return '<span class="tag frozen">❄️ congelé' + (b.frozenAt ? ' le ' + esc(fmtDate(b.frozenAt)) : '') + '</span>';
    return expiryTag(b.exp) + (b.opened ? ' <span class="tag opened">entamé</span>' : '');
  }
  function lotStatus(b) { return b.frozen ? 'frozen' : status(b.exp); }
  function kcalText(k) { return Math.round(k).toLocaleString('fr-FR') + ' kcal'; }
  /** « · 539 kcal/100 g » ou « · 75 kcal/pièce » (vide si inconnu). */
  function kcalInfo(p) {
    if (typeof p.kcal100 !== 'number') return '';
    if (p.unit === 'pièce') {
      var k = L.kcalOf(p, 1, 'pièce');
      return k === null ? '' : ' · ' + kcalText(k) + '/pièce';
    }
    return ' · ' + kcalText(p.kcal100) + '/100 ' + (L.baseUnit(p.unit) === 'ml' ? 'ml' : 'g');
  }

  /** Vignette : photo prise, photo Open Food Facts, ou initiale. */
  function thumb(item, big) {
    var cls = 'thumb' + (big ? ' big' : '');
    var src = item.photo || item.photoUrl;
    if (src) return '<div class="' + cls + '" style="background-image:url(\'' + esc(src) + '\')"></div>';
    var name = item.name || '?';
    return '<div class="' + cls + '">' + esc(name.charAt(0).toUpperCase()) + '</div>';
  }

  function options(list, selected) {
    return list.map(function (v) {
      return '<option value="' + esc(v) + '"' + (v === selected ? ' selected' : '') + '>' + esc(v) + '</option>';
    }).join('');
  }

  function plural(n, word) { return n + ' ' + word + (n > 1 ? 's' : ''); }

  // ======================================================================
  // Message en bas + annulation
  // ======================================================================
  var toastTimer = null;
  var undoFn = null;
  function showToast(message, onUndo, label) {
    $('toast-btn').textContent = label || 'Annuler';
    $('toast-text').textContent = message;
    undoFn = onUndo || null;
    $('toast-btn').className = onUndo ? '' : 'hidden';
    $('toast').className = '';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, onUndo ? 8000 : 3500);
  }
  function hideToast() { $('toast').className = 'hidden'; undoFn = null; }

  // ======================================================================
  // Fenêtres (modales)
  // ======================================================================
  var modalHandlers = {};
  var modalOnClose = null;
  function openModal(html, handlers, onClose) {
    modalHandlers = handlers || {};
    modalOnClose = onClose || null;
    $('modal-box').innerHTML = html;
    $('modal').className = '';
    $('modal').scrollTop = 0;
  }
  function closeModal(silent) {
    $('modal').className = 'hidden';
    $('modal-box').innerHTML = '';
    modalHandlers = {};
    var cb = modalOnClose;
    modalOnClose = null;
    if (cb && !silent) cb();
  }

  function askConfirm(title, message, okLabel, onOk) {
    openModal('<h3>' + esc(title) + '</h3><p>' + esc(message) + '</p>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="m-ok">' + esc(okLabel) + '</button></div>',
      { 'm-ok': function () { closeModal(true); onOk(); } });
  }

  function askText(title, initial, onOk) {
    openModal('<h3>' + esc(title) + '</h3><div class="field"><input type="text" id="m-text" value="' + esc(initial || '') + '"></div>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="m-ok">OK</button></div>',
      { 'm-ok': function () { var v = $('m-text').value.trim(); closeModal(true); if (v) onOk(v); } });
    setTimeout(function () { var i = $('m-text'); if (i) i.focus(); }, 50);
  }

  function askQuantity(title, unit, initial, max, onOk) {
    openModal('<h3>' + esc(title) + '</h3>' +
      '<div class="field"><label>Quantité (' + esc(unit) + ')</label>' +
      '<input type="text" inputmode="decimal" id="m-qty" value="' + esc(L.formatNumber(initial)) + '"></div>' +
      (max !== null && max !== undefined ? '<p class="muted">En stock : ' + esc(qty(max, unit)) + '</p>' : '') +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="m-ok">Valider</button></div>',
      {
        'm-ok': function () {
          var v = L.parseNumber($('m-qty').value);
          if (v === null || v <= 0) { $('m-qty').focus(); return; }
          closeModal(true);
          onOk(v);
        }
      });
    setTimeout(function () { var i = $('m-qty'); if (i) { i.focus(); i.select(); } }, 50);
  }

  // ======================================================================
  // Photos (réduites, et redressées : iOS 12 ne tourne pas les photos tout seul)
  // ======================================================================
  function jpegOrientation(buffer) {
    try {
      var v = new DataView(buffer);
      if (v.getUint16(0) !== 0xFFD8) return 1;
      var off = 2;
      while (off < v.byteLength) {
        var marker = v.getUint16(off);
        off += 2;
        if (marker === 0xFFE1) {
          if (v.getUint32(off + 2) !== 0x45786966) return 1;
          var tiff = off + 8;
          var little = v.getUint16(tiff) === 0x4949;
          var ifd = tiff + v.getUint32(tiff + 4, little);
          var n = v.getUint16(ifd, little);
          for (var i = 0; i < n; i++) {
            var e = ifd + 2 + i * 12;
            if (v.getUint16(e, little) === 0x0112) return v.getUint16(e + 8, little);
          }
          return 1;
        } else if ((marker & 0xFF00) !== 0xFF00) {
          return 1;
        } else {
          off += v.getUint16(off);
        }
      }
    } catch (err) { /* ignore */ }
    return 1;
  }

  function resizePhoto(file, cb) {
    var reader = new FileReader();
    reader.onload = function () {
      var orientation = jpegOrientation(reader.result);
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        var max = 240;
        var w = img.naturalWidth, h = img.naturalHeight;
        var scale = Math.min(1, max / Math.max(w, h));
        var cw = Math.round(w * scale), ch = Math.round(h * scale);
        // Les navigateurs récents redressent déjà l'image : on ne le refait pas.
        var autoRotated = (typeof CSS !== 'undefined' && CSS.supports && CSS.supports('image-orientation', 'from-image'));
        var rotate = !autoRotated && orientation >= 5 && orientation <= 8;
        var canvas = document.createElement('canvas');
        canvas.width = rotate ? ch : cw;
        canvas.height = rotate ? cw : ch;
        var ctx = canvas.getContext('2d');
        if (!autoRotated) {
          switch (orientation) {
            case 3: ctx.transform(-1, 0, 0, -1, cw, ch); break;
            case 6: ctx.transform(0, 1, -1, 0, ch, 0); break;
            case 8: ctx.transform(0, -1, 1, 0, 0, cw); break;
            default: break;
          }
        }
        ctx.drawImage(img, 0, 0, cw, ch);
        URL.revokeObjectURL(url);
        cb(canvas.toDataURL('image/jpeg', 0.7));
      };
      img.onerror = function () { URL.revokeObjectURL(url); cb(null); };
      img.src = url;
    };
    reader.readAsArrayBuffer(file);
  }

  // ======================================================================
  // Stock : ajout, consommation
  // ======================================================================
  /** Ajoute un lot ; réutilise le produit existant (code-barres, sinon nom). */
  function addStock(o) {
    var p = o.barcode ? productByBarcode(o.barcode) : null;
    if (!p) p = productByName(o.name);
    if (p && o.barcode && p.barcode && p.barcode !== o.barcode) p = null;
    var q = o.qty;
    if (!p) {
      p = {
        id: newId(), name: o.name, brand: o.brand || '', barcode: o.barcode || '',
        category: o.category, unit: o.unit, photoUrl: o.photoUrl || '', photo: o.photo || '',
        pending: !!(o.pending && o.barcode), placeholder: !!o.placeholder,
        kcal100: typeof o.kcal100 === 'number' ? o.kcal100 : null,
        packQty: o.packQty || null, packUnit: o.packUnit || null
      };
      db.products.push(p);
    } else {
      p.category = o.category;
      if (typeof o.kcal100 === 'number') p.kcal100 = o.kcal100;
      if (o.packQty && !p.packQty) { p.packQty = o.packQty; p.packUnit = o.packUnit; }
      if (o.brand) p.brand = o.brand;
      if (o.barcode) p.barcode = o.barcode;
      if (o.photoUrl && !p.photoUrl) p.photoUrl = o.photoUrl;
      if (o.photo) p.photo = o.photo;
      var c = L.convert(o.qty, o.unit, p.unit);
      if (c !== null) q = c;
      else if (totalOf(p.id) === 0) p.unit = o.unit;
    }
    var lot = { id: newId(), productId: p.id, qty: q, exp: o.exp, added: new Date().toISOString() };
    if (o.frozen) { lot.frozen = true; lot.frozenAt = L.todayKey(); }
    if (o.location) lot.location = o.location;
    db.batches.push(lot);
    return p;
  }

  /** Nouvelles quantités (0 = lot supprimé). Un paquet en g/ml dont on n'a
   *  utilisé qu'une partie devient « entamé ». */
  function applyQuantities(newQ) {
    db.batches = db.batches.filter(function (b) {
      if (!(b.id in newQ)) return true;
      if (newQ[b.id] <= 0) return false;
      if (newQ[b.id] < b.qty && !b.opened && !b.frozen) {
        var p = productById(b.productId);
        if (p && p.unit !== 'pièce') { b.opened = true; b.openedAt = L.todayKey(); }
      }
      b.qty = newQ[b.id];
      return true;
    });
  }

  function useProduct(pid, amount) {
    var p = productById(pid);
    var total = totalOf(pid);
    function go(q) {
      var snap = snapshot();
      applyQuantities(L.consumeFefo(batchesOf(pid), q).newQuantities);
      var left = totalOf(pid);
      commitWithUndo(left <= 0 ? p.name + ' : stock épuisé'
        : p.name + ' : ' + qty(Math.min(q, total), p.unit) + ' en moins, reste ' + qty(left, p.unit), snap);
    }
    if (amount) go(amount);
    else askQuantity('Utiliser « ' + p.name + ' »', p.unit, p.unit === 'pièce' ? 1 : total, total, go);
  }

  /** Retire du stock les ingrédients d'une recette, pour `people` personnes. */
  function consumeRecipe(r, people) {
    var f = L.portionFactor(r, people);
    var newQ = {};
    r.ingredients.forEach(function (ing) {
      var p = L.matchProduct(ing, db.products);
      if (!p) return;
      var q = L.convert(ing.qty * f, ing.unit, p.unit);
      if (q === null) return;
      var lots = batchesOf(p.id).map(function (b) {
        return { id: b.id, qty: (b.id in newQ) ? newQ[b.id] : b.qty, exp: b.exp, added: b.added, frozen: b.frozen };
      }).filter(function (b) { return b.qty > 0; });
      var res = L.consumeFefo(lots, q).newQuantities;
      Object.keys(res).forEach(function (k) { newQ[k] = res[k]; });
    });
    applyQuantities(newQ);
  }

  // ======================================================================
  // Emplacements (facultatifs)
  // ======================================================================
  /** Emplacement proposé : congelé ou Surgelé → congélateur, Frais → frigo, sinon placard. */
  function defaultLocation(category, frozen) {
    var locs = db.settings.locations;
    function pick(name, idx) { return locs.indexOf(name) >= 0 ? name : (locs[idx] || locs[0] || ''); }
    if (frozen || category === mapCategory('Surgelé')) return pick('Congélateur', 1);
    if (category === mapCategory('Frais')) return pick('Frigo', 0);
    return pick('Placard', 2);
  }
  function lotLocation(b) { return b.location || ''; }
  function locationField(id, selected) {
    if (!db.settings.useLocations) return '';
    return '<div class="field"><label>Emplacement</label><select id="' + id + '">' +
      options(db.settings.locations, selected) + '</select></div>';
  }

  // ======================================================================
  // Courses → stock
  // ======================================================================
  /** Ouvre la fiche d'ajout préremplie avec un article acheté ; il quitte la liste une fois rangé. */
  function shoppingToStock(itemId) {
    var i = find(db.shopping, itemId);
    if (!i) return;
    var p = productByName(i.name);
    openArticleForm({
      product: p, fromShopping: i.id,
      prefill: { name: i.name, qty: i.qty, unit: i.unit }
    });
  }

  // ======================================================================
  // Lecture de la date sur une photo (OCR, sans internet)
  // ======================================================================
  // Règle : on ne propose QUE des dates réellement lues ; sinon, saisie à la main.
  var ocr = { script: null };

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  /** Photo → image en niveaux de gris, contrastée et redressée (lisible par l'OCR). */
  function photoForOcr(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        var orientation = jpegOrientation(reader.result);
        var url = URL.createObjectURL(file);
        var img = new Image();
        img.onload = function () {
          var max = 1600;
          var w = img.naturalWidth, h = img.naturalHeight;
          var scale = Math.min(1, max / Math.max(w, h));
          var cw = Math.round(w * scale), ch = Math.round(h * scale);
          var autoRotated = (typeof CSS !== 'undefined' && CSS.supports && CSS.supports('image-orientation', 'from-image'));
          var rotate = !autoRotated && orientation >= 5 && orientation <= 8;
          var c = document.createElement('canvas');
          c.width = rotate ? ch : cw;
          c.height = rotate ? cw : ch;
          var ctx = c.getContext('2d');
          if (!autoRotated) {
            if (orientation === 3) ctx.transform(-1, 0, 0, -1, cw, ch);
            else if (orientation === 6) ctx.transform(0, 1, -1, 0, ch, 0);
            else if (orientation === 8) ctx.transform(0, -1, 1, 0, 0, cw);
          }
          ctx.drawImage(img, 0, 0, cw, ch);
          URL.revokeObjectURL(url);
          // niveaux de gris + étirement du contraste
          var d = ctx.getImageData(0, 0, c.width, c.height);
          var px = d.data, lo = 255, hi = 0, i, g;
          for (i = 0; i < px.length; i += 4) {
            g = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
            px[i] = g;
            if (g < lo) lo = g;
            if (g > hi) hi = g;
          }
          var range = Math.max(1, hi - lo);
          for (i = 0; i < px.length; i += 4) {
            g = (px[i] - lo) * 255 / range;
            px[i] = px[i + 1] = px[i + 2] = g;
          }
          ctx.putImageData(d, 0, 0);
          resolve(c.toDataURL('image/jpeg', 0.92));
        };
        img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('image')); };
        img.src = url;
      };
      reader.onerror = reject;
      reader.readAsArrayBuffer(file);
    });
  }

  function readDateFromPhoto(file) {
    var box = $('f-ocr');
    function say(html) { var b = $('f-ocr'); if (b) b.innerHTML = html; }
    say('⏳ Préparation de la lecture… (peut prendre jusqu\'à 30 secondes sur cet iPad)');
    if (!ocr.script) ocr.script = loadScript('vendor/ocr/tesseract.min.js');
    var worker = null;
    ocr.script.then(function () {
      return photoForOcr(file);
    }).then(function (image) {
      say('⏳ Lecture de la photo…');
      return window.Tesseract.createWorker('eng', 1, {
        workerPath: 'vendor/ocr/worker.min.js',
        corePath: 'vendor/ocr/tesseract-core-lstm.wasm.js',
        langPath: 'vendor/ocr',
        gzip: true,
        cacheMethod: 'none',
        logger: function (m) {
          if (m && m.status === 'recognizing text') say('⏳ Lecture de la photo… ' + Math.round((m.progress || 0) * 100) + ' %');
        }
      }).then(function (w) {
        worker = w;
        return w.recognize(image);
      });
    }).then(function (res) {
      if (worker) worker.terminate();
      var dates = L.findDates(res && res.data ? res.data.text : '');
      if (!box || !$('f-ocr')) return;
      if (!dates.length) {
        say('❌ Aucune date lisible sur cette photo. Rapproche-toi de la date (bien nette, sans reflet) ou saisis-la à la main.');
        return;
      }
      say((dates.length === 1 ? 'Date lue sur la photo :' : 'Plusieurs dates lues — choisis la bonne :') +
        '<div class="wrap" style="margin-top:6px">' + dates.map(function (d) {
          return '<button class="btn small primary" data-action="f-usedate" data-key="' + d.key + '">' +
            esc(fmtDate(d.key)) + (d.monthOnly ? ' (fin du mois)' : '') + '</button>';
        }).join('') + '</div><div style="margin-top:4px">Texte lu : « ' + esc(dates.map(function (d) { return d.text; }).join(' / ')) +
        ' ». Vérifie avant de valider.</div>');
    }).catch(function () {
      if (worker) worker.terminate();
      say('❌ La lecture n\'a pas marché sur cet appareil. Saisis la date à la main.');
    });
  }

  // ======================================================================
  // Formulaire d'ajout d'article (manuel, nouveau lot, ou après un scan)
  // ======================================================================
  var form = null; // état du formulaire ouvert

  function openArticleForm(opts) {
    var p = opts.product || null;
    var off = opts.off || null;
    var today = L.todayKey();
    form = {
      opts: opts,
      photo: p ? p.photo : '',
      photoUrl: p ? p.photoUrl : (off ? off.imageUrl : ''),
      existing: p
    };
    var cats = db.settings.categories;
    var cat = p ? p.category : mapCategory(off ? off.category : 'Autre');
    if (cats.indexOf(cat) < 0) cat = mapCategory('Autre');
    var name = p ? p.name : (off ? off.name : '');
    var brand = p ? p.brand : (off ? off.brand : '');
    // Quantité proposée d'après l'emballage : « 4 x 125 g » → 4 pièces, « 400 g » → 400 g.
    var sugg = { qty: 1, unit: p ? p.unit : 'pièce' };
    if (p && p.unit !== 'pièce' && p.packQty && L.convert(p.packQty, p.packUnit, p.unit) !== null) {
      sugg = { qty: L.convert(p.packQty, p.packUnit, p.unit), unit: p.unit };
    } else if (!p && off && off.pack) {
      sugg = L.suggestQuantity(off.pack);
    }
    form.pack = off && off.pack ? { qty: off.pack.each, unit: off.pack.unit } : null;
    if (opts.prefill) {
      if (!p) name = opts.prefill.name;
      if (opts.prefill.qty) {
        var pu = opts.prefill.unit || 'pièce';
        var cq = p ? L.convert(opts.prefill.qty, pu, p.unit) : null;
        sugg = cq !== null ? { qty: cq, unit: p.unit } : { qty: opts.prefill.qty, unit: pu };
      }
    }
    var kcal = p && typeof p.kcal100 === 'number' ? p.kcal100 : (off && typeof off.kcal100 === 'number' ? off.kcal100 : null);
    var quick = [['+3 j', 3], ['+1 sem.', 7], ['+2 sem.', 14], ['+1 mois', 30], ['+6 mois', 182], ['+1 an', 365]];

    openModal(
      '<h3>' + (opts.fromScan ? 'Article scanné' : (p ? 'Ajouter un lot' : 'Ajouter un article')) + '</h3>' +
      (opts.message ? '<p class="warn">' + esc(opts.message) + '</p>' : '') +
      (off && off.local ? '<p class="note">Trouvé dans la base de produits de l\'appli (sans internet).</p>' : '') +
      '<div class="row field">' +
      '<label style="margin:0" id="f-photo-prev">' + thumb({ name: name, photo: form.photo, photoUrl: form.photoUrl }, true) + '</label>' +
      '<div class="grow">' +
      '<div class="field"><label>Nom du produit</label><input type="text" id="f-name" value="' + esc(name) + '"' + (p ? ' readonly' : '') + ' autocomplete="off"' +
      (opts.optionalName ? ' placeholder="Vide = rempli plus tard"' : '') + '></div>' +
      '<div class="field" style="margin:0"><label>Marque (facultatif)</label><input type="text" id="f-brand" value="' + esc(brand) + '"' + (p ? ' readonly' : '') + '></div>' +
      '</div></div>' +
      '<div class="field"><label class="btn small" style="display:inline-block;color:var(--green)">📷 Photo<input type="file" id="f-photo" accept="image/*" class="hidden"></label></div>' +
      (opts.barcode ? '<p class="muted">Code-barres : ' + esc(opts.barcode) + '</p>' : '') +
      (off && off.quantityText ? '<p class="muted">Contenance indiquée : ' + esc(off.quantityText) + '</p>' : '') +
      '<div id="f-hint"></div>' +
      '<div class="field"><label>Catégorie</label><select id="f-cat">' + options(cats, cat) + '</select></div>' +
      '<div class="two field">' +
      '<div><label class="muted">Quantité</label><input type="text" inputmode="decimal" id="f-qty" value="' + esc(L.formatNumber(sugg.qty)) + '"></div>' +
      '<div><label class="muted">Unité</label><select id="f-unit"></select></div>' +
      '</div>' +
      '<div class="field"><label>Calories pour 100 g ou 100 ml (facultatif)</label>' +
      '<input type="text" inputmode="decimal" id="f-kcal" value="' + (kcal === null ? '' : esc(L.formatNumber(kcal))) + '" placeholder="ex. 250"></div>' +
      '<label class="row field" style="font-size:16px"><input type="checkbox" id="f-frozen" class="check"><span>❄️ Je le mets au congélateur (la date ne comptera plus)</span></label>' +
      locationField('f-loc', defaultLocation(cat, false)) +
      '<div class="field"><label>À consommer avant le</label><input type="date" id="f-date" value="' + L.addDays(today, 7) + '"></div>' +
      '<div class="field"><label class="btn small" style="display:inline-block">📷 Lire la date sur l\'emballage' +
      '<input type="file" id="f-ocr-file" accept="image/*" class="hidden"></label>' +
      '<div id="f-ocr" class="muted" style="margin-top:6px"></div></div>' +
      '<div class="wrap field">' + quick.map(function (x) {
        return '<button class="chip" data-action="f-quick" data-days="' + x[1] + '">' + x[0] + '</button>';
      }).join('') + '</div>' +
      '<div class="actions">' +
      '<button class="btn" data-action="modal-close">' + (opts.fromScan ? 'Ignorer' : 'Annuler') + '</button>' +
      '<button class="btn primary" data-action="f-save">' + (opts.fromScan ? 'Ajouter et continuer' : 'Ajouter au stock') + '</button>' +
      '</div>',
      {
        'f-save': saveArticleForm,
        'f-quick': function (el) { $('f-date').value = L.addDays(L.todayKey(), Number(el.getAttribute('data-days'))); }
      },
      function () { form = null; if (opts.fromScan) resumeScan(false); }
    );
    updateFormUnits(sugg.unit);
    updateFormHint();
    if (!p && !opts.fromScan) setTimeout(function () { var i = $('f-name'); if (i) i.focus(); }, 50);
  }

  /** Si le produit existe déjà avec du stock, on ne propose que des unités compatibles. */
  function updateFormUnits(preferred) {
    var sel = $('f-unit');
    if (!sel || !form) return;
    var ex = form.existing;
    var allowed = (ex && totalOf(ex.id) > 0)
      ? L.UNITS.filter(function (u) { return L.baseUnit(u) === L.baseUnit(ex.unit); })
      : L.UNITS;
    var cur = preferred || sel.value;
    if (allowed.indexOf(cur) < 0) cur = ex ? ex.unit : allowed[0];
    sel.innerHTML = options(allowed, cur);
  }

  function updateFormHint() {
    if (!form || form.opts.product) return;
    var nameInput = $('f-name');
    var match = productByName(nameInput.value);
    if (match && form.opts.barcode && match.barcode && match.barcode !== form.opts.barcode) match = null;
    var changed = match !== form.existing;
    form.existing = match;
    $('f-hint').innerHTML = match
      ? '<p class="note">Déjà connu : un nouveau lot sera ajouté à « ' + esc(match.name) + ' ».</p>' : '';
    if (changed) {
      if (match) {
        $('f-cat').value = match.category;
        updateFormUnits(match.unit);
      } else {
        updateFormUnits();
      }
    }
  }

  function saveArticleForm() {
    var name = $('f-name').value.trim();
    var q = L.parseNumber($('f-qty').value);
    var exp = $('f-date').value;
    var opts = form.opts;
    var placeholder = false;
    if (!name && opts.optionalName && opts.barcode) {
      name = 'Produit ' + opts.barcode + ' (à compléter)';
      placeholder = true;
    }
    if (!name) { $('f-name').focus(); return; }
    if (q === null || q <= 0) { $('f-qty').focus(); return; }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(exp)) { $('f-date').focus(); return; }
    var kcal = L.parseNumber($('f-kcal').value);
    addStock({
      pending: !!opts.pending,
      placeholder: placeholder,
      kcal100: kcal !== null && kcal >= 0 ? kcal : null,
      packQty: form.pack ? form.pack.qty : null,
      packUnit: form.pack ? form.pack.unit : null,
      frozen: $('f-frozen').checked,
      location: $('f-loc') ? $('f-loc').value : '',
      name: name,
      brand: $('f-brand').value.trim(),
      barcode: opts.barcode || (opts.product ? opts.product.barcode : ''),
      category: $('f-cat').value,
      unit: $('f-unit').value,
      photo: form.photo,
      photoUrl: form.photoUrl,
      qty: q,
      exp: exp
    });
    form = null;
    closeModal(true);
    commit();
    completePending();
    if (opts.fromScan) {
      scan.count++;
      resumeScan(true);
      showToast(name + ' ajouté');
    } else {
      showToast('Article ajouté au stock');
    if (opts.fromShopping) {
      db.shopping = db.shopping.filter(function (i) { return i.id !== opts.fromShopping; });
      commit();
    }
    }
  }

  function openProductEdit(pid) {
    var p = productById(pid);
    form = { photo: p.photo, photoUrl: p.photoUrl, editing: p };
    var cats = db.settings.categories.slice();
    if (cats.indexOf(p.category) < 0) cats.push(p.category);
    openModal('<h3>Modifier le produit</h3>' +
      '<div class="row field"><div id="f-photo-prev">' + thumb(p, true) + '</div>' +
      '<div class="grow"><label class="btn small" style="display:inline-block">📷 Changer la photo<input type="file" id="f-photo" accept="image/*" class="hidden"></label>' +
      '<div style="margin-top:8px"><button class="btn small danger" data-action="p-nophoto">Retirer la photo</button></div></div></div>' +
      '<div class="field"><label>Nom</label><input type="text" id="p-name" value="' + esc(p.name) + '"></div>' +
      '<div class="field"><label>Marque</label><input type="text" id="p-brand" value="' + esc(p.brand || '') + '"></div>' +
      '<div class="field"><label>Catégorie</label><select id="p-cat">' + options(cats, p.category) + '</select></div>' +
      '<div class="field"><label>Calories pour 100 g ou 100 ml</label><input type="text" inputmode="decimal" id="p-kcal" value="' +
      (typeof p.kcal100 === 'number' ? esc(L.formatNumber(p.kcal100)) : '') + '" placeholder="inconnu"></div>' +
      (p.unit === 'pièce'
        ? '<div class="field"><label>Poids ou volume d\'une pièce (pour calculer les calories)</label><div class="two">' +
          '<input type="text" inputmode="decimal" id="p-pack" value="' + (p.packQty ? esc(L.formatNumber(p.packQty)) : '') + '" placeholder="ex. 125">' +
          '<select id="p-packunit">' + options(['g', 'ml'], L.baseUnit(p.packUnit || 'g') === 'ml' ? 'ml' : 'g') + '</select></div></div>'
        : '') +
      '<div class="field"><label>Toujours en avoir au moins (' + esc(p.unit) + ') — ajouté aux courses en dessous</label>' +
      '<input type="text" inputmode="decimal" id="p-min" value="' + (p.minQty ? esc(L.formatNumber(p.minQty)) : '') + '" placeholder="pas de minimum" style="max-width:160px"></div>' +
      (p.barcode ? '<p class="muted">Code-barres : ' + esc(p.barcode) + '</p>' : '') +
      '<p class="muted">Unité : ' + esc(p.unit) + '</p>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="p-save">Enregistrer</button></div>',
      {
        'p-nophoto': function () {
          form.photo = ''; form.photoUrl = '';
          $('f-photo-prev').innerHTML = thumb({ name: p.name }, true);
        },
        'p-save': function () {
          var n = $('p-name').value.trim();
          if (!n) return;
          p.name = n;
          p.brand = $('p-brand').value.trim();
          p.category = $('p-cat').value;
          p.photo = form.photo;
          p.photoUrl = form.photoUrl;
          var mq = L.parseNumber($('p-min').value);
          p.minQty = mq && mq > 0 ? mq : null;
          var k = L.parseNumber($('p-kcal').value);
          p.kcal100 = k !== null && k >= 0 ? k : null;
          if ($('p-pack')) {
            var w = L.parseNumber($('p-pack').value);
            p.packQty = w && w > 0 ? w : null;
            p.packUnit = p.packQty ? $('p-packunit').value : null;
          }
          form = null;
          closeModal(true);
          commit();
        }
      }, function () { form = null; });
  }

  function openLotEdit(bid) {
    var b = find(db.batches, bid);
    var p = productById(b.productId);
    var today = L.todayKey();
    function earlier(days) { var d = L.addDays(today, days); return d < b.exp ? d : b.exp; }
    openModal('<h3>Lot de ' + esc(p.name) + '</h3>' +
      '<div class="field"><label>Quantité (' + esc(p.unit) + ')</label><input type="text" inputmode="decimal" id="l-qty" value="' + esc(L.formatNumber(b.qty)) + '"></div>' +
      locationField('l-loc', b.location || defaultLocation(p.category, b.frozen)) +
      (b.frozen
        ? '<p class="note">❄️ Congelé' + (b.frozenAt ? ' le ' + esc(fmtDate(b.frozenAt)) : '') + ' : la date de péremption ne compte pas.</p>' +
          '<input type="hidden" id="l-date" value="' + esc(b.exp) + '">' +
          '<div class="wrap field"><button class="btn" data-action="l-thaw">Décongeler (à consommer sous 24 h)</button></div>'
        : '<div class="field"><label>À consommer avant le</label><input type="date" id="l-date" value="' + esc(b.exp) + '"></div>' +
          '<label class="row field" style="font-size:16px"><input type="checkbox" id="l-opened" class="check"' + (b.opened ? ' checked' : '') + '><span>Entamé</span></label>' +
          '<div class="field"><label>Une fois ouvert, à finir sous :</label><div class="wrap">' +
          [[2, '2 j'], [3, '3 j'], [5, '5 j'], [7, '1 sem.'], [30, '1 mois']].map(function (x) {
            return '<button class="chip" data-action="l-open" data-days="' + x[0] + '">' + x[1] + '</button>';
          }).join('') + '</div></div>' +
          '<div class="wrap field"><button class="btn" data-action="l-freeze">❄️ Congeler</button></div>') +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="l-save">Enregistrer</button></div>',
      {
        // « Entamé » + date raccourcie (sans jamais la repousser)
        'l-open': function (el) {
          $('l-opened').checked = true;
          $('l-date').value = earlier(Number(el.getAttribute('data-days')));
        },
        'l-freeze': function () {
          closeModal(true);
          b.frozen = true;
          b.frozenAt = today;
          if (db.settings.useLocations) b.location = defaultLocation(p.category, true);
          commit();
          showToast(p.name + ' : congelé, la date ne compte plus');
        },
        'l-thaw': function () {
          closeModal(true);
          b.frozen = false;
          b.frozenAt = null;
          b.exp = L.addDays(today, 1);
          commit();
          showToast(p.name + ' : décongelé, à consommer avant demain');
        },
        'l-save': function () {
          var q = L.parseNumber($('l-qty').value);
          var d = $('l-date').value;
          if (q === null || q < 0 || !/^\d{4}-\d{2}-\d{2}$/.test(d)) return;
          var snap = snapshot();
          closeModal(true);
          if (q === 0) {
            applyQuantities(makeObj(b.id, 0));
            commitWithUndo('Lot supprimé', snap);
          } else {
            b.qty = q;
            b.exp = d;
            if ($('l-loc')) b.location = $('l-loc').value;
            if ($('l-opened')) {
              var op = $('l-opened').checked;
              if (op && !b.opened) b.openedAt = today;
              b.opened = op;
            }
            commit();
          }
        }
      });
  }

  function makeObj(k, v) { var o = {}; o[k] = v; return o; }

  // ======================================================================
  // Scanner (caméra + Open Food Facts)
  // ======================================================================
  var scan = { reader: null, busy: false, last: '', lastTime: 0, count: 0 };
  var audioCtx = null;

  function unlockAudio() {
    try {
      var C = window.AudioContext || window.webkitAudioContext;
      if (!C) return;
      if (!audioCtx) audioCtx = new C();
      if (audioCtx.state === 'suspended') audioCtx.resume();
      // iOS : il faut jouer un son (même vide) pendant un appui pour débloquer l'audio.
      var buf = audioCtx.createBuffer(1, 1, 22050);
      var src = audioCtx.createBufferSource();
      src.buffer = buf;
      src.connect(audioCtx.destination);
      src.start(0);
    } catch (e) { /* pas de son, tant pis */ }
  }

  function beep() {
    try {
      if (!audioCtx) return;
      var o = audioCtx.createOscillator();
      var g = audioCtx.createGain();
      o.frequency.value = 1200;
      g.gain.value = 0.15;
      o.connect(g);
      g.connect(audioCtx.destination);
      o.start(0);
      o.stop(audioCtx.currentTime + 0.12);
    } catch (e) { /* ignore */ }
    if (navigator.vibrate) navigator.vibrate(80);
  }

  function setScanMessage(html) { $('scan-msg').innerHTML = html; }
  function updateScanCount() {
    $('scan-count').textContent = scan.count ? plural(scan.count, 'article') + ' ajouté' + (scan.count > 1 ? 's' : '') : '';
  }

  function openScanner() {
    unlockAudio();
    scan.count = 0;
    scan.busy = false;
    updateScanCount();
    $('scanner').className = '';
    $('scan-frame').className = '';
    setScanMessage('Vise le code-barres. La caméra reste ouverte pour enchaîner les articles.');
    var typeBtn = '<br><button class="btn primary" data-action="scan-type">⌨️ Taper le code-barres</button>';
    if (window.navigator.standalone) {
      setScanMessage("Sur cet iPad, la caméra ne marche que dans Safari.<br>Ouvre l'appli dans Safari (pas depuis l'icône plein écran)." + typeBtn);
      return;
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.ZXing) {
      setScanMessage('La caméra n\'est pas disponible ici.' + typeBtn);
      return;
    }
    try {
      var Z = window.ZXing;
      var hints = new Map();
      hints.set(Z.DecodeHintType.POSSIBLE_FORMATS,
        [Z.BarcodeFormat.EAN_13, Z.BarcodeFormat.EAN_8, Z.BarcodeFormat.UPC_A, Z.BarcodeFormat.UPC_E]);
      scan.reader = new Z.BrowserMultiFormatReader(hints, 250);
      scan.reader.decodeFromConstraints(
        { audio: false, video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } } },
        'scan-video',
        function (result) { if (result) onScanCode(result.getText()); }
      ).catch(function (err) {
        var denied = err && (err.name === 'NotAllowedError' || err.name === 'SecurityError');
        setScanMessage((denied
          ? "L'accès à la caméra a été refusé.<br>Réglages de l'iPad → Safari → Appareil photo → Autoriser, puis recharge la page."
          : 'Impossible de démarrer la caméra.') + typeBtn);
      });
    } catch (e) {
      setScanMessage('Impossible de démarrer la caméra.' + typeBtn);
    }
  }

  function closeScanner() {
    try { if (scan.reader) scan.reader.reset(); } catch (e) { /* ignore */ }
    scan.reader = null;
    $('scanner').className = 'hidden';
    render();
  }

  function onScanCode(code) {
    if (scan.busy) return;
    var now = Date.now();
    if (code === scan.last && now - scan.lastTime < 3000) return;
    scan.last = code;
    scan.lastTime = now;
    scan.busy = true;
    $('scan-frame').className = 'hit';
    beep();
    handleBarcode(code, true);
  }

  function resumeScan() {
    scan.busy = false;
    scan.lastTime = Date.now(); // laisse le temps d'enlever l'article de la caméra
    $('scan-frame').className = '';
    updateScanCount();
  }

  function fetchWithTimeout(url, ms) {
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () { reject(new Error('timeout')); }, ms);
      fetch(url).then(function (r) { clearTimeout(t); resolve(r); }, function (e) { clearTimeout(t); reject(e); });
    });
  }

  /** Calories pour 100 g/ml d'après les données nutritionnelles d'Open Food Facts. */
  function kcalFrom(n) {
    if (!n) return null;
    var k = n['energy-kcal_100g'];
    if (typeof k !== 'number' && typeof n['energy_100g'] === 'number') k = n['energy_100g'] / 4.184; // kJ → kcal
    return (typeof k === 'number' && k >= 0 && k < 1000) ? Math.round(k) : null;
  }

  function lookupOff(code) {
    var url = 'https://world.openfoodfacts.org/api/v2/product/' + encodeURIComponent(code) +
      '.json?lc=fr&fields=product_name,product_name_fr,generic_name_fr,brands,image_front_small_url,image_front_url,categories_tags,quantity,nutriments';
    return fetchWithTimeout(url, 10000).then(function (res) {
      if (res.status === 404) return null;
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    }).then(function (body) {
      if (!body || body.status !== 1 || !body.product) return null;
      var p = body.product;
      function str(k) { var v = p[k]; return (typeof v === 'string' && v.trim()) ? v.trim() : ''; }
      var name = str('product_name_fr') || str('product_name') || str('generic_name_fr');
      if (!name) return null;
      var q = L.parseOffQuantity(str('quantity'));
      return {
        name: name,
        brand: str('brands').split(',')[0].trim(),
        imageUrl: str('image_front_small_url') || str('image_front_url'),
        category: L.mapOffCategory(Array.isArray(p.categories_tags) ? p.categories_tags : []),
        quantity: q ? q[0] : null,
        unit: q ? q[1] : null,
        quantityText: str('quantity'),
        pack: L.parsePack(str('quantity')),
        kcal100: kcalFrom(p.nutriments)
      };
    });
  }

  // ---- Base de produits embarquée (hors ligne) ----
  // Fichier data/products-fr.tsv : code, nom, marque, n° catégorie, contenance, image.
  var localDb = { map: null, loading: null, count: 0 };

  function loadLocalDb() {
    if (localDb.map) return Promise.resolve(localDb.map);
    if (localDb.loading) return localDb.loading;
    localDb.loading = fetch('data/products-fr.tsv').then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    }).then(function (text) {
      var map = {};
      var n = 0;
      var start = 0;
      while (start < text.length) {
        var end = text.indexOf('\n', start);
        if (end < 0) end = text.length;
        var tab = text.indexOf('\t', start);
        if (tab > start && tab < end) {
          map[text.slice(start, tab)] = text.slice(tab + 1, end);
          n++;
        }
        start = end + 1;
      }
      localDb.map = map;
      localDb.count = n;
      return map;
    }).catch(function () {
      localDb.loading = null;
      return null;
    });
    return localDb.loading;
  }

  function offImageUrl(code, file) {
    if (!file) return '';
    var folder = code;
    if (code.length > 8) {
      var c = code;
      while (c.length < 13) c = '0' + c;
      folder = c.slice(0, 3) + '/' + c.slice(3, 6) + '/' + c.slice(6, 9) + '/' + c.slice(9);
    }
    return 'https://images.openfoodfacts.org/images/products/' + folder + '/' + file;
  }

  function lookupLocal(code) {
    return loadLocalDb().then(function (map) {
      var line = map ? map[code] : null;
      if (!line) return null;
      var f = line.split('\t');
      var q = L.parseOffQuantity(f[3]);
      return {
        name: f[0],
        brand: f[1] || '',
        category: L.DEFAULT_CATEGORIES[Number(f[2])] || 'Autre',
        quantity: q ? q[0] : null,
        unit: q ? q[1] : null,
        quantityText: f[3] || '',
        pack: L.parsePack(f[3]),
        kcal100: f[5] ? Number(f[5]) : null,
        imageUrl: offImageUrl(code, f[4]),
        local: true
      };
    });
  }

  /** Cherche d'abord dans la base embarquée (instantané, sans internet),
   *  sinon sur Open Food Facts si on a internet. */
  function handleBarcode(code, fromScan) {
    var known = productByBarcode(code);
    if (known) {
      openArticleForm({ product: known, barcode: code, fromScan: fromScan });
      return;
    }
    var stillOpen = function () { return $('modal').className !== 'hidden'; };
    openModal('<h3>Recherche du produit…</h3><p class="muted">Code-barres ' + esc(code) + '</p>', {},
      function () { if (fromScan) resumeScan(); });
    lookupLocal(code).then(function (local) {
      if (!stillOpen()) return;
      if (local) {
        closeModal(true);
        openArticleForm({ off: local, barcode: code, fromScan: fromScan, pending: true });
        return;
      }
      if (navigator.onLine === false) {
        closeModal(true);
        openArticleForm({ barcode: code, fromScan: fromScan, pending: true, optionalName: true,
          message: 'Pas de connexion : laisse le nom vide, il sera rempli tout seul à la prochaine connexion (ou tape-le).' });
        return;
      }
      lookupOff(code).then(function (off) {
        if (!stillOpen()) return;
        closeModal(true);
        openArticleForm({ off: off, barcode: code, fromScan: fromScan,
          message: off ? '' : "Produit inconnu d'Open Food Facts : complète la fiche." });
      }, function () {
        if (!stillOpen()) return;
        closeModal(true);
        openArticleForm({ barcode: code, fromScan: fromScan, pending: true, optionalName: true,
          message: 'Pas de connexion : laisse le nom vide, il sera rempli tout seul à la prochaine connexion (ou tape-le).' });
      });
    });
  }

  /** Complète les fiches créées hors ligne (nom, photo, marque) dès qu'internet revient. */
  var completing = false;
  function completePending() {
    if (completing || navigator.onLine === false) return;
    var todo = db.products.filter(function (p) { return p.pending && p.barcode; }).slice(0, 25);
    if (!todo.length) return;
    completing = true;
    var changed = 0;
    var i = 0;
    function next() {
      if (i >= todo.length) {
        completing = false;
        if (changed) {
          save();
          render();
          showToast(changed === 1 ? '1 fiche produit complétée' : changed + ' fiches produits complétées');
        }
        return;
      }
      var p = todo[i++];
      lookupOff(p.barcode).then(function (off) {
        if (off) {
          if (p.placeholder) {
            p.name = off.name;
            p.placeholder = false;
            if (p.category === mapCategory('Autre')) p.category = mapCategory(off.category);
          }
          if (!p.brand) p.brand = off.brand;
          if (typeof p.kcal100 !== 'number' && typeof off.kcal100 === 'number') p.kcal100 = off.kcal100;
          if (!p.packQty && off.pack) { p.packQty = off.pack.each; p.packUnit = off.pack.unit; }
          if (!p.photo && off.imageUrl) p.photoUrl = off.imageUrl;
          changed++;
        }
        p.pending = false; // trouvé ou inconnu : on ne redemande pas
        next();
      }, function () {
        completing = false; // plus de réseau : on réessaiera plus tard
        if (changed) { save(); render(); }
      });
    }
    next();
  }

  function askBarcode(fromScan) {
    if (fromScan) scan.busy = true;
    openModal('<h3>Saisir le code-barres</h3>' +
      '<div class="field"><input type="text" inputmode="numeric" id="m-code" placeholder="ex. 3017620422003"></div>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="m-ok">Chercher</button></div>',
      {
        'm-ok': function () {
          var c = $('m-code').value.replace(/\D/g, '');
          if (!c) return;
          closeModal(true);
          handleBarcode(c, fromScan);
        }
      }, function () { if (fromScan) resumeScan(); });
    setTimeout(function () { var i = $('m-code'); if (i) i.focus(); }, 50);
  }

  // ======================================================================
  // Recettes
  // ======================================================================
  var recipeRows = null;

  function openRecipeForm(rid) {
    var r = rid ? recipeById(rid) : null;
    form = { photo: r ? r.photo : '', recipe: r };
    recipeRows = r ? r.ingredients.map(function (i) { return { name: i.name, qty: L.formatNumber(i.qty), unit: i.unit }; }) : [];
    if (!recipeRows.length) recipeRows.push({ name: '', qty: '1', unit: 'pièce' });
    var names = db.products.map(function (p) { return p.name; }).sort();
    openModal('<h3>' + (r ? 'Modifier la recette' : 'Nouvelle recette') + '</h3>' +
      '<datalist id="dl-products">' + names.map(function (n) { return '<option value="' + esc(n) + '">'; }).join('') + '</datalist>' +
      '<div class="row field"><div id="f-photo-prev">' + thumb({ name: r ? r.name : '+', photo: form.photo }, true) + '</div>' +
      '<div class="grow"><label>Nom de la recette</label><input type="text" id="r-name" value="' + esc(r ? r.name : '') + '">' +
      '<label class="btn small" style="display:inline-block;margin-top:8px">📷 Photo<input type="file" id="f-photo" accept="image/*" class="hidden"></label></div></div>' +
      '<div class="field"><label>Pour combien de personnes ? (les quantités ci-dessous)</label>' +
      '<input type="text" inputmode="numeric" id="r-serv" value="' + (r ? (r.servings || '') : '4') + '" placeholder="ex. 4" style="max-width:120px"></div>' +
      '<h3 style="font-size:17px;margin:8px 0 4px">Ingrédients</h3>' +
      '<p class="muted" style="margin-top:0">Écris le nom comme dans ton stock pour le relier automatiquement (une liste te propose les produits connus).</p>' +
      '<div id="r-rows"></div>' +
      '<button class="btn small" data-action="r-addrow">+ Ajouter un ingrédient</button>' +
      '<div class="field" style="margin-top:14px"><label>Préparation</label><textarea id="r-instr">' + esc(r ? r.instructions : '') + '</textarea></div>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="r-save">Enregistrer</button></div>',
      {
        'r-addrow': function () { readRecipeRows(); recipeRows.push({ name: '', qty: '1', unit: 'pièce' }); renderRecipeRows(true); },
        'r-delrow': function (el) { readRecipeRows(); recipeRows.splice(Number(el.getAttribute('data-i')), 1); renderRecipeRows(); },
        'r-save': saveRecipeForm
      }, function () { form = null; recipeRows = null; });
    renderRecipeRows();
  }

  function renderRecipeRows(focusLast) {
    $('r-rows').innerHTML = recipeRows.map(function (row, i) {
      return '<div class="two field">' +
        '<div style="flex:3"><input type="text" class="r-n" list="dl-products" placeholder="Ingrédient ' + (i + 1) + '" value="' + esc(row.name) + '"></div>' +
        '<div style="flex:1.2"><input type="text" class="r-q" inputmode="decimal" value="' + esc(row.qty) + '"></div>' +
        '<div style="flex:1.3"><select class="r-u">' + options(L.UNITS, row.unit) + '</select></div>' +
        '<div style="flex:0 0 44px"><button class="icon-btn" data-action="r-delrow" data-i="' + i + '">✕</button></div>' +
        '</div>';
    }).join('');
    if (focusLast) {
      var inputs = document.querySelectorAll('#r-rows .r-n');
      if (inputs.length) inputs[inputs.length - 1].focus();
    }
  }

  function readRecipeRows() {
    var n = document.querySelectorAll('#r-rows .r-n');
    var q = document.querySelectorAll('#r-rows .r-q');
    var u = document.querySelectorAll('#r-rows .r-u');
    recipeRows = [];
    for (var i = 0; i < n.length; i++) recipeRows.push({ name: n[i].value, qty: q[i].value, unit: u[i].value });
  }

  function saveRecipeForm() {
    readRecipeRows();
    var name = $('r-name').value.trim();
    if (!name) { $('r-name').focus(); return; }
    var ings = [];
    recipeRows.forEach(function (row) {
      var n = row.name.trim();
      if (!n) return;
      var p = productByName(n);
      var q = L.parseNumber(row.qty);
      ings.push({ name: n, qty: q && q > 0 ? q : 1, unit: row.unit, productId: p ? p.id : null });
    });
    var r = form.recipe;
    if (!r) { r = { id: newId() }; db.recipes.push(r); }
    r.name = name;
    r.ingredients = ings;
    r.instructions = $('r-instr').value.trim();
    r.photo = form.photo;
    var serv = Math.round(L.parseNumber($('r-serv').value) || 0);
    r.servings = serv > 0 ? serv : null;
    form = null;
    recipeRows = null;
    closeModal(true);
    commit();
    showToast('Recette enregistrée');
  }

  function missingCount(r) {
    return L.computeNeeds([{ recipeId: r.id }], makeObj(r.id, r), db.products, db.batches)
      .filter(function (n) { return n.missing > 0; }).length;
  }

  /** Recette faite : PROPOSE de retirer les ingrédients du stock (jamais automatique). */
  function cookRecipe(r, entry, peopleArg) {
    var people = entry ? entry.people : peopleArg;
    var f = L.portionFactor(r, people);
    var lines = [];
    var any = false;
    r.ingredients.forEach(function (ing0) {
      var ing = { name: ing0.name, qty: ing0.qty * f, unit: ing0.unit, productId: ing0.productId };
      var p = L.matchProduct(ing, db.products);
      var total = p ? totalOf(p.id) : 0;
      var wanted = p ? L.convert(ing.qty, ing.unit, p.unit) : null;
      if (!p || total <= 0 || wanted === null) {
        lines.push('<li>' + esc(ing.name) + ' : pas en stock (ignoré)</li>');
        return;
      }
      any = true;
      lines.push('<li>' + (wanted <= total + 1e-9
        ? esc(qty(ing.qty, ing.unit)) + ' de ' + esc(p.name)
        : esc(p.name) + ' : tout le stock (' + esc(qty(total, p.unit)) + ', il en fallait ' + esc(qty(ing.qty, ing.unit)) + ')') + '</li>');
    });
    function finish(consume) {
      var snap = snapshot();
      closeModal(true);
      if (entry) entry.done = true;
      if (consume) {
        consumeRecipe(r, people);
        commitWithUndo('Stock mis à jour pour « ' + r.name + ' »', snap);
      } else {
        commit();
        showToast('« ' + r.name + ' » marquée comme faite');
      }
    }
    openModal('<h3>« ' + esc(r.name) + ' » est faite ?</h3>' +
      (people ? '<p class="muted">Pour ' + plural(people, 'personne') + '</p>' : '') +
      '<p>' + (any ? 'Retirer ces quantités du stock ?' : "Aucun ingrédient de cette recette n'est en stock.") + '</p>' +
      '<ul>' + lines.join('') + '</ul>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn" data-action="c-keep">Ne rien retirer</button>' +
      (any ? '<button class="btn primary" data-action="c-consume">Retirer du stock</button>' : '') + '</div>',
      { 'c-keep': function () { finish(false); }, 'c-consume': function () { finish(true); } });
  }

  function pickRecipe(title, onPick) {
    var list = db.recipes.slice().sort(function (a, b) { return a.name.localeCompare(b.name, 'fr'); });
    if (!list.length) { showToast("Crée d'abord une recette dans l'onglet Recettes."); return; }
    openModal('<h3>' + esc(title) + '</h3>' + list.map(function (r) {
      return '<button class="option" data-action="m-pick" data-id="' + r.id + '">' + esc(r.name) + '</button>';
    }).join('') + '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button></div>',
      { 'm-pick': function (el) { var r = recipeById(el.getAttribute('data-id')); closeModal(true); onPick(r); } });
  }

  function peopleField(r) {
    var n = ui.people[r.id] || r.servings || 2;
    return '<div class="field"><label>Nombre de personnes</label>' +
      '<input type="text" inputmode="numeric" id="m-people" value="' + n + '" style="max-width:120px"></div>';
  }
  function readPeople() {
    var n = Math.round(L.parseNumber($('m-people') ? $('m-people').value : '') || 0);
    return n > 0 ? n : null;
  }

  function planRecipe(r) {
    var today = L.todayKey();
    if (!db.settings.planByDay) {
      openModal('<h3>Ajouter « ' + esc(r.name) + ' » au planning</h3>' + peopleField(r) +
        '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
        '<button class="btn primary" data-action="m-ok">Ajouter</button></div>',
        { 'm-ok': function () {
          var n = readPeople();
          closeModal(true);
          db.plan.push({ id: newId(), recipeId: r.id, date: null, done: false, people: n });
          commit();
          showToast('« ' + r.name + ' » ajoutée au planning');
        } });
      return;
    }
    var html = '<h3>Planifier « ' + esc(r.name) + ' »</h3>' + peopleField(r);
    for (var i = 0; i < 8; i++) {
      var k = L.addDays(today, i);
      html += '<button class="option" data-action="m-day" data-day="' + k + '">' +
        (i === 0 ? "Aujourd'hui" : i === 1 ? 'Demain' : fmtDay(k)) + '</button>';
    }
    html += '<div class="field" style="margin-top:12px"><label>Autre date</label><div class="two">' +
      '<input type="date" id="m-date" value="' + today + '"><button class="btn primary" data-action="m-other" style="flex:0 0 auto">OK</button></div></div>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button></div>';
    function add(day) {
      var n = readPeople();
      closeModal(true);
      db.plan.push({ id: newId(), recipeId: r.id, date: day, done: false, people: n });
      commit();
      showToast('« ' + r.name + ' » prévue ' + fmtDay(day).toLowerCase());
    }
    openModal(html, {
      'm-day': function (el) { add(el.getAttribute('data-day')); },
      'm-other': function () { var d = $('m-date').value; if (/^\d{4}-\d{2}-\d{2}$/.test(d)) add(d); }
    });
  }

  // ======================================================================
  // Sauvegarde
  // ======================================================================
  function exportText() {
    return JSON.stringify({ format: BACKUP_FORMAT, version: 1, exportedAt: new Date().toISOString(), data: db });
  }

  function openExport() {
    var text = exportText();
    var name = 'stock_alimentaire_' + L.todayKey() + '.json';
    var href = 'data:application/json;charset=utf-8,' + encodeURIComponent(text);
    openModal('<h3>Exporter une sauvegarde</h3>' +
      '<p>Copie tout le texte ci-dessous et colle-le dans une note (appli Notes) ou un e-mail à toi-même. ' +
      'Pour restaurer : Réglages → Importer, puis colle ce texte.</p>' +
      '<textarea id="x-text" readonly style="min-height:160px;font-size:12px">' + esc(text) + '</textarea>' +
      '<p class="muted">' + Math.round(text.length / 1024) + ' Ko</p>' +
      '<div class="actions"><a class="btn" href="' + href + '" download="' + name + '" style="text-decoration:none;display:inline-block">Fichier</a>' +
      '<button class="btn" data-action="modal-close">Fermer</button>' +
      '<button class="btn primary" data-action="x-copy">Copier</button></div>',
      {
        'x-copy': function () {
          var t = $('x-text');
          t.removeAttribute('readonly');
          t.focus();
          t.setSelectionRange(0, t.value.length);
          var ok = false;
          try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
          t.setAttribute('readonly', '');
          t.blur();
          showToast(ok ? 'Sauvegarde copiée : colle-la dans Notes ou un e-mail.' : 'Sélectionne le texte et copie-le à la main.');
        }
      });
  }

  function openImport() {
    openModal('<h3>Importer une sauvegarde</h3>' +
      '<p class="warn">Attention : remplace TOUTES les données actuelles (stock, recettes, planning, courses).</p>' +
      '<div class="field"><label>Fichier de sauvegarde</label><input type="file" id="i-file" accept=".json,application/json,text/plain"></div>' +
      '<div class="field"><label>… ou colle le texte de la sauvegarde</label><textarea id="i-text"></textarea></div>' +
      '<div class="actions"><button class="btn" data-action="modal-close">Annuler</button>' +
      '<button class="btn primary" data-action="i-go">Importer</button></div>',
      { 'i-go': function () { doImport($('i-text').value); } });
  }

  function doImport(text) {
    var parsed;
    try { parsed = JSON.parse(text); } catch (e) { showToast("Ce texte n'est pas une sauvegarde valide."); return; }
    if (!parsed || parsed.format !== BACKUP_FORMAT || !parsed.data) {
      showToast("Ce n'est pas une sauvegarde de Stock Alimentaire.");
      return;
    }
    var snap = snapshot();
    db = normalizeDb(parsed.data);
    closeModal(true);
    commitWithUndo('Sauvegarde importée', snap);
  }

  // ======================================================================
  // Écrans
  // ======================================================================
  var ui = { tab: 'stock', search: '', category: null, sort: 'expiry', expanded: {}, recipeId: null, weekStart: L.todayKey(), people: {} };

  var TITLES = { stock: 'Mon stock', expiring: 'Bientôt périmés', recipes: 'Recettes', planning: 'Planning', shopping: 'Liste de courses', settings: 'Réglages' };

  function render() {
    var btns = document.querySelectorAll('#tabs button');
    for (var i = 0; i < btns.length; i++) {
      btns[i].className = btns[i].getAttribute('data-tab') === ui.tab ? 'active' : '';
    }
    var exp = expiringBatches().length;
    var toBuy = db.shopping.filter(function (s) { return !s.checked; }).length;
    $('badge-expiring').textContent = exp ? String(exp) : '';
    $('badge-shopping').textContent = toBuy ? String(toBuy) : '';

    var title = TITLES[ui.tab];
    var actions = '';
    var fabs = '';
    var body = '';
    if (ui.tab === 'stock') {
      actions = '<button class="topbtn" data-action="sort">' + (ui.sort === 'expiry' ? '↕ Date' : '↕ Nom') + '</button>';
      fabs = '<button class="btn" data-action="add-manual">✏️ Ajouter</button>' +
        '<button class="btn primary" data-action="scan-open">📷 Scanner</button>';
      body = viewStock();
    } else if (ui.tab === 'expiring') {
      body = viewExpiring();
    } else if (ui.tab === 'recipes') {
      var r = ui.recipeId ? recipeById(ui.recipeId) : null;
      if (r) {
        title = r.name;
        actions = '<button class="topbtn" data-action="recipe-back">‹ Retour</button>';
        body = viewRecipe(r);
      } else {
        ui.recipeId = null;
        fabs = '<button class="btn primary" data-action="recipe-new">＋ Nouvelle recette</button>';
        body = viewRecipes();
      }
    } else if (ui.tab === 'planning') {
      if (!db.settings.planByDay) fabs = '<button class="btn primary" data-action="plan-add">＋ Ajouter une recette</button>';
      body = viewPlanning();
    } else if (ui.tab === 'shopping') {
      actions = db.shopping.some(function (s) { return s.checked; })
        ? '<button class="topbtn" data-action="shop-clear">Retirer les cochés</button>' : '';
      body = viewShopping();
    } else {
      body = viewSettings();
    }
    $('title').textContent = title;
    $('top-actions').innerHTML = actions;
    $('fabs').innerHTML = fabs;
    $('view').innerHTML = body;
  }

  // ---- Stock ----
  function stockProducts() {
    var q = L.normalizeName(ui.search);
    var list = productsInStock().filter(function (p) {
      if (ui.category && p.category !== ui.category) return false;
      if (db.settings.useLocations && ui.location &&
          !batchesOf(p.id).some(function (b) { return lotLocation(b) === ui.location; })) return false;
      return !q || L.normalizeName(p.name + ' ' + (p.brand || '')).indexOf(q) >= 0;
    });
    var nearest = {};
    list.forEach(function (p) {
      var first = batchesOf(p.id)[0];
      nearest[p.id] = first.frozen ? '9999-12-31' : first.exp; // tout congelé : en fin de liste
    });
    list.sort(function (a, b) {
      if (ui.sort === 'name') return a.name.localeCompare(b.name, 'fr');
      return nearest[a.id] < nearest[b.id] ? -1 : nearest[a.id] > nearest[b.id] ? 1 : 0;
    });
    return list;
  }

  function viewStock() {
    var all = productsInStock();
    if (!all.length) {
      return '<div class="empty"><span class="big">🥫</span>Ton stock est vide.<br>Appuie sur « Scanner » pour ajouter tes premiers articles.</div>';
    }
    var cats = {};
    all.forEach(function (p) { cats[p.category] = true; });
    var order = db.settings.categories.filter(function (c) { return cats[c]; });
    Object.keys(cats).forEach(function (c) { if (order.indexOf(c) < 0) order.push(c); });

    var exp = expiringBatches();
    var anyExpired = exp.some(function (b) { return L.daysUntil(b.exp) < 0; });
    var html = '<div class="search"><input type="search" id="search" placeholder="🔍 Rechercher un produit" value="' + esc(ui.search) + '" autocomplete="off"></div>';
    if (order.length > 1) {
      html += '<div class="chips"><button class="chip' + (ui.category ? '' : ' on') + '" data-action="cat" data-cat="">Tout</button>' +
        order.map(function (c) {
          return '<button class="chip' + (ui.category === c ? ' on' : '') + '" data-action="cat" data-cat="' + esc(c) + '">' + esc(c) + '</button>';
        }).join('') + '</div>';
    }
    if (db.settings.useLocations) {
      html += '<div class="chips"><button class="chip' + (ui.location ? '' : ' on') + '" data-action="loc" data-loc="">📍 Partout</button>' +
        db.settings.locations.map(function (l) {
          return '<button class="chip' + (ui.location === l ? ' on' : '') + '" data-action="loc" data-loc="' + esc(l) + '">' + esc(l) + '</button>';
        }).join('') + '</div>';
    }
    var low = L.belowMinimum(db.products, db.batches);
    if (low.length) {
      html += '<button class="banner orange" data-action="tab" data-tab="shopping">🛒 Sous le stock minimum : ' +
        esc(low.slice(0, 3).map(function (p) { return p.name; }).join(', ')) + (low.length > 3 ? '…' : '') + ' ›</button>';
    }
    if (exp.length) {
      html += '<button class="banner ' + (anyExpired ? 'red' : 'orange') + '" data-action="tab" data-tab="expiring">⚠️ ' +
        (exp.length === 1 ? '1 lot ' : exp.length + ' lots ') + (anyExpired ? 'périmé(s) ou à consommer vite' : 'à consommer vite') + ' ›</button>';
    }
    html += '<div id="stock-list">' + stockListHtml() + '</div>';
    return html;
  }

  function stockListHtml() {
    var list = stockProducts();
    if (!list.length) return '<div class="empty">Aucun produit ne correspond.</div>';
    return list.map(productCard).join('');
  }

  function productCard(p) {
    var lots = batchesOf(p.id);
    var total = lots.reduce(function (s, b) { return s + b.qty; }, 0);
    var open = !!ui.expanded[p.id];
    var html = '<div class="card">' +
      '<div class="row prod-head" data-action="toggle" data-id="' + p.id + '">' + thumb(p) +
      '<div class="grow"><div class="name">' + esc(p.name) + '</div>' +
      '<div class="muted">' + esc(qty(total, p.unit)) + ' au total' + (lots.length > 1 ? ' · ' + lots.length + ' lots' : '') +
      kcalInfo(p) + '</div>' +
      '<div style="margin-top:3px">' + lotTag(lots[0]) + '</div></div>' +
      '<button class="icon-btn" data-action="use" data-id="' + p.id + '" title="Utiliser">➖</button>' +
      '</div>';
    if (open) {
      html += '<div class="lots">' + lots.map(function (b) {
        return '<div class="row lot"><span class="dot ' + lotStatus(b) + '"></span>' +
          '<div class="grow" data-action="lot-edit" data-id="' + b.id + '"><b>' + esc(qty(b.qty, p.unit)) + '</b>' +
          (b.opened && !b.frozen ? ' <span class="tag opened">entamé</span>' : '') +
          '<div class="muted">' + (b.frozen
            ? '❄️ congelé' + (b.frozenAt ? ' le ' + esc(fmtDate(b.frozenAt)) : '') + ' · la date ne compte pas'
            : 'avant le ' + esc(fmtDate(b.exp)) + ' · ' + esc(L.expiryLabel(L.daysUntil(b.exp)))) +
          (db.settings.useLocations ? ' · 📍 ' + esc(b.location || 'emplacement ?') : '') + '</div></div>' +
          '<button class="icon-btn" data-action="lot-edit" data-id="' + b.id + '" title="Modifier, entamé, congeler">⋯</button>' +
          '<button class="icon-btn" data-action="lot-del" data-id="' + b.id + '">🗑</button></div>';
      }).join('') +
        '<div class="wrap" style="margin-top:6px">' +
        '<button class="btn small" data-action="use-ask" data-id="' + p.id + '">🍴 Utiliser…</button>' +
        '<button class="btn small" data-action="add-lot" data-id="' + p.id + '">＋ Ajouter un lot</button>' +
        '<button class="btn small" data-action="prod-edit" data-id="' + p.id + '">✏️ Modifier</button>' +
        '<button class="btn small danger" data-action="prod-clear" data-id="' + p.id + '">Tout retirer</button>' +
        '</div></div>';
    }
    return html + '</div>';
  }

  // ---- Bientôt périmés ----
  function viewExpiring() {
    var lots = expiringBatches();
    var a = db.settings.alertDays;
    if (!lots.length) return '<div class="empty"><span class="big">👍</span>Rien ne périme dans les ' + a + ' prochains jours.</div>';
    var expired = lots.filter(function (b) { return L.daysUntil(b.exp) < 0; });
    var soon = lots.filter(function (b) { return L.daysUntil(b.exp) >= 0; });
    function card(b) {
      var p = productById(b.productId);
      if (!p) return '';
      return '<div class="card pad row">' + thumb(p) +
        '<div class="grow"><div class="name">' + esc(p.name) + '</div>' +
        '<div class="muted">' + esc(qty(b.qty, p.unit)) + ' · ' + esc(fmtDate(b.exp)) + '</div>' +
        '<div style="margin-top:3px">' + lotTag(b) + '</div></div>' +
        '<div class="right"><button class="btn small" data-action="exp-use" data-id="' + b.id + '">Utilisé</button>' +
        '<div style="height:8px"></div><button class="btn small danger" data-action="exp-trash" data-id="' + b.id + '">Jeté</button></div></div>';
    }
    var html = '';
    if (expired.length) html += '<h2 class="red">Périmés</h2>' + expired.map(card).join('');
    if (soon.length) html += '<h2 class="orange">À consommer dans les ' + a + ' jours</h2>' + soon.map(card).join('');
    return html;
  }

  // ---- Recettes ----
  function viewRecipes() {
    if (!db.recipes.length) return '<div class="empty"><span class="big">📖</span>Aucune recette pour le moment.<br>Ajoute ta première recette !</div>';
    return db.recipes.slice().sort(function (a, b) { return a.name.localeCompare(b.name, 'fr'); }).map(function (r) {
      var m = missingCount(r);
      var n = r.ingredients.length;
      var k = L.recipeKcal(r, db.products);
      return '<div class="card pad row" data-action="recipe-open" data-id="' + r.id + '">' + thumb(r) +
        '<div class="grow"><div class="name">' + esc(r.name) + '</div><div class="muted">' + plural(n, 'ingrédient') +
        (r.servings ? ' · ' + plural(r.servings, 'personne') : '') +
        (n ? (m ? ' · ' + m + ' manquant' + (m > 1 ? 's' : '') : ' · tout est en stock') : '') + '</div>' +
        (k.total > 0 && k.perPerson ? '<div class="kcal">≈ ' + kcalText(k.perPerson) + ' par personne</div>' : '') + '</div>' +
        '<span style="font-size:22px">' + (n && !m ? '✅' : '🧺') + '</span></div>';
    }).join('');
  }

  function viewRecipe(r) {
    var html = '';
    if (r.photo) html += '<div class="card" style="height:220px;background:url(\'' + esc(r.photo) + '\') center/cover"></div>';
    html += '<div class="wrap" style="margin-bottom:8px">' +
      '<button class="btn primary" data-action="recipe-plan" data-id="' + r.id + '">📅 Planifier</button>' +
      '<button class="btn" data-action="recipe-cook" data-id="' + r.id + '">🍳 Je l\'ai cuisinée</button>' +
      '<button class="btn" data-action="recipe-edit" data-id="' + r.id + '">✏️ Modifier</button>' +
      '<button class="btn danger" data-action="recipe-del" data-id="' + r.id + '">Supprimer</button></div>';
    var people = ui.people[r.id] || r.servings || 0;
    var f = L.portionFactor(r, people);
    var k = L.recipeKcal(r, db.products, people || undefined);
    html += '<div class="card pad">' +
      (r.servings
        ? '<div class="row"><b class="grow">Pour</b><button class="icon-btn" data-action="r-people" data-id="' + r.id + '" data-delta="-1">➖</button>' +
          '<b>' + plural(people, 'personne') + '</b><button class="icon-btn" data-action="r-people" data-id="' + r.id + '" data-delta="1">➕</button></div>'
        : '<div class="muted">Indique le nombre de personnes dans « Modifier » pour ajuster les quantités.</div>') +
      '<div style="margin-top:6px">🔥 ' + (k.total > 0
        ? '<b>≈ ' + kcalText(k.total) + '</b> au total' + (k.perPerson ? ' · <b>' + kcalText(k.perPerson) + '</b> par personne' : '')
        : 'Calories inconnues') +
      (k.unknown ? '<div class="muted">' + plural(k.unknown, 'ingrédient') + ' sans calories connues (non compté' + (k.unknown > 1 ? 's' : '') + ')</div>' : '') +
      '</div></div>';
    html += '<h2>Ingrédients</h2><div class="card">';
    if (!r.ingredients.length) html += '<div class="list-item muted">Aucun ingrédient.</div>';
    r.ingredients.forEach(function (ing0) {
      var ing = { name: ing0.name, qty: ing0.qty * f, unit: ing0.unit, productId: ing0.productId };
      var p = L.matchProduct(ing, db.products);
      var ik = L.kcalOf(p, ing.qty, ing.unit);
      var base = L.baseUnit(ing.unit);
      var ok = p && L.availableQuantity(p, db.batches, base) + 1e-9 >= L.convert(ing.qty, ing.unit, base);
      html += '<div class="list-item row"><span style="font-size:20px">' + (ok ? '✅' : '❌') + '</span><div class="grow">' +
        '<b>' + esc(qty(ing.qty, ing.unit)) + '</b> — ' + esc(ing.name) +
        '<div class="muted">' + (p ? 'En stock : ' + esc(qty(L.availableQuantity(p, db.batches, p.unit), p.unit)) + ' (' + esc(p.name) + ')' : 'Pas dans le stock') +
        (ik !== null ? ' · ' + kcalText(ik) : '') + '</div></div></div>';
    });
    html += '</div><h2>Préparation</h2><div class="card pad" style="white-space:pre-wrap">' + (r.instructions ? esc(r.instructions) : '—') + '</div>';
    return html;
  }

  // ---- Planning ----
  function viewPlanning() {
    var byDay = db.settings.planByDay;
    var html = '<div class="wrap" style="justify-content:center;margin-bottom:8px">' +
      '<button class="chip' + (byDay ? ' on' : '') + '" data-action="plan-mode" data-mode="day">📆 Par jour</button>' +
      '<button class="chip' + (!byDay ? ' on' : '') + '" data-action="plan-mode" data-mode="list">📝 Liste libre</button></div>';
    html += needsCard();
    var entries = db.plan.filter(function (e) { return recipeById(e.recipeId); });
    var today = L.todayKey();
    if (byDay) {
      var end = L.addDays(ui.weekStart, 6);
      html += '<div class="row" style="margin:8px 0"><button class="icon-btn" data-action="week" data-delta="-7">◀</button>' +
        '<div class="grow" style="text-align:center;font-weight:600">Du ' + esc(fmtDate(ui.weekStart)) + ' au ' + esc(fmtDate(end)) + '</div>' +
        '<button class="icon-btn" data-action="week" data-delta="7">▶</button></div>';
      var late = entries.filter(function (e) { return e.date && e.date < today && !e.done; });
      if (late.length && ui.weekStart <= today) html += daySection('Jours passés, pas encore faites', late, null);
      for (var i = 0; i < 7; i++) {
        var k = L.addDays(ui.weekStart, i);
        html += daySection(k === today ? "Aujourd'hui" : fmtDay(k), entries.filter(function (e) { return e.date === k; }), k);
      }
      var undated = entries.filter(function (e) { return !e.date; });
      if (undated.length) html += daySection('Sans date', undated, null);
    } else {
      entries.sort(function (a, b) { return (a.done ? 1 : 0) - (b.done ? 1 : 0); });
      html += daySection('Recettes prévues', entries, null, true);
    }
    if (db.plan.some(function (e) { return e.done; })) {
      html += '<div style="text-align:center;margin-top:12px"><button class="btn small" data-action="plan-cleardone">Retirer les recettes faites</button></div>';
    }
    return html;
  }

  function needsCard() {
    var pending = db.plan.filter(function (e) { return !e.done && recipeById(e.recipeId); });
    if (!pending.length) return '<div class="banner green">ℹ️ Aucune recette prévue. Ajoute des recettes pour voir ce qui manque dans ton stock.</div>';
    var missing = currentNeeds().filter(function (n) { return n.missing > 0; });
    if (!missing.length) return '<div class="banner green">✅ Tout est en stock pour les recettes prévues.</div>';
    function f(q, base) { var h = L.humanize(q, base); return qty(h[0], h[1]); }
    return '<div class="banner red">🧺 Il faut acheter ' + plural(missing.length, 'ingrédient') + '<ul>' +
      missing.map(function (n) {
        return '<li>' + esc(n.name) + ' : il manque ' + esc(f(n.missing, n.unit)) +
          (n.available > 0 ? ' (en stock : ' + esc(f(n.available, n.unit)) + ')' : '') + '</li>';
      }).join('') + '</ul><button class="btn small" data-action="tab" data-tab="shopping">🛒 Voir la liste de courses</button></div>';
  }

  function daySection(title, entries, dayKey, showDate) {
    var html = '<div class="card"><div class="row pad" style="padding-bottom:4px"><b class="grow">' + esc(title) + '</b>' +
      (dayKey ? '<button class="icon-btn" data-action="plan-add" data-day="' + dayKey + '">＋</button>' : '') + '</div>';
    if (!entries.length) html += '<div class="list-item muted" style="padding-top:0">—</div>';
    entries.forEach(function (e) {
      var r = recipeById(e.recipeId);
      var n = e.people || r.servings;
      var sub = [];
      if (showDate && e.date) sub.push(fmtDay(e.date));
      if (n) {
        var kk = L.recipeKcal(r, db.products, n);
        sub.push(n + ' pers.' + (kk.perPerson && kk.total > 0 ? ' · ' + kcalText(kk.perPerson) + '/pers.' : ''));
      }
      if (e.done) sub.push('Faite');
      html += '<div class="list-item row">' +
        '<div class="grow" data-action="plan-open" data-id="' + r.id + '"><span class="' + (e.done ? 'done' : '') + '">' + esc(r.name) + '</span>' +
        (sub.length ? '<div class="muted">' + esc(sub.join(' · ')) + '</div>' : '') + '</div>' +
        (e.done ? '' : '<button class="icon-btn" data-action="plan-people" data-id="' + e.id + '" title="Nombre de personnes">👥</button>') +
        (e.done ? '' : '<button class="btn small" data-action="plan-done" data-id="' + e.id + '">✓ Faite</button>') +
        '<button class="icon-btn" data-action="plan-del" data-id="' + e.id + '">✕</button></div>';
    });
    return html + '</div>';
  }

  // ---- Courses ----
  function viewShopping() {
    var html = '<div class="card pad"><div class="two">' +
      '<div style="flex:3"><input type="text" id="s-name" placeholder="Ajouter un article…"></div>' +
      '<div style="flex:1.2"><input type="text" id="s-qty" inputmode="decimal" placeholder="Qté"></div>' +
      '<div style="flex:1.3"><select id="s-unit">' + options(L.UNITS, 'pièce') + '</select></div>' +
      '<div style="flex:0 0 auto"><button class="btn primary" data-action="shop-add">＋</button></div></div></div>';
    var items = db.shopping.slice().sort(function (a, b) {
      if (a.checked !== b.checked) return a.checked ? 1 : -1;
      return a.name.localeCompare(b.name, 'fr');
    });
    if (!items.length) {
      return html + '<div class="empty"><span class="big">🛒</span>Rien à acheter.<br>Les ingrédients manquants du planning apparaîtront ici automatiquement.</div>';
    }
    html += '<div class="card">' + items.map(function (i) {
      var sub = [];
      if (i.qty !== null && i.qty !== undefined) sub.push(qty(i.qty, i.unit || 'pièce'));
      if (i.auto) sub.push(i.why === 'min' ? 'stock minimum' : (i.why === 'both' ? 'planning + stock minimum' : 'pour le planning'));
      return '<div class="list-item row">' +
        '<input type="checkbox" class="check" data-action="shop-check" data-id="' + i.id + '"' + (i.checked ? ' checked' : '') + '>' +
        '<div class="grow" data-action="shop-check" data-id="' + i.id + '"><span class="' + (i.checked ? 'done' : '') + '">' + esc(i.name) + '</span>' +
        (sub.length ? '<div class="muted">' + esc(sub.join(' · ')) + '</div>' : '') + '</div>' +
        (i.checked ? '<button class="btn small" data-action="shop-stock" data-id="' + i.id + '">＋ Stock</button>' : '') +
        '<button class="icon-btn" data-action="shop-del" data-id="' + i.id + '">🗑</button></div>';
    }).join('') + '</div>';
    return html;
  }

  // ---- Réglages ----
  function viewSettings() {
    var s = db.settings;
    var used = {};
    db.products.forEach(function (p) { used[p.category] = true; });
    var html = '';
    html += '<div class="banner green">📱 <b>Installer sur l\'écran d\'accueil</b><br><span style="font-weight:400">Dans Safari : bouton Partager (carré avec une flèche) → « Sur l\'écran d\'accueil ». ' +
      'L\'icône ouvrira l\'appli dans Safari, ce qui permet d\'utiliser la caméra.<br>' +
      '📴 L\'appli marche <b>sans internet</b> : seule la recherche du nom d\'un produit scanné inconnu a besoin du réseau.</span></div>';
    html += '<h2>Alertes de péremption</h2><div class="card pad row"><div class="grow">Prévenir ' + plural(s.alertDays, 'jour') + ' avant la date' +
      '<div class="muted">Pastille orange et onglet « Bientôt périmés »</div></div>' +
      '<button class="icon-btn" data-action="alert" data-delta="-1">➖</button><b>' + s.alertDays + '</b>' +
      '<button class="icon-btn" data-action="alert" data-delta="1">➕</button></div>';
    html += '<h2>Catégories</h2><div class="card">' + s.categories.map(function (c, i) {
      return '<div class="list-item row"><div class="grow">' + esc(c) + '</div>' +
        '<button class="icon-btn" data-action="cat-rename" data-i="' + i + '">✏️</button>' +
        (used[c] || s.categories.length <= 1 ? '<span class="muted" style="width:44px;text-align:center">—</span>'
          : '<button class="icon-btn" data-action="cat-del" data-i="' + i + '">🗑</button>') + '</div>';
    }).join('') + '<div class="list-item"><button class="btn small" data-action="cat-add">＋ Ajouter une catégorie</button></div></div>';
    html += '<h2>Emplacements</h2><div class="card">' +
      '<label class="list-item row" style="font-size:17px"><input type="checkbox" class="check" data-action="loc-toggle"' + (s.useLocations ? ' checked' : '') + '>' +
      '<span class="grow">Ranger les produits par emplacement (frigo, congélateur, placard…)</span></label>' +
      (s.useLocations ? s.locations.map(function (l, i) {
        var usedL = db.batches.some(function (b) { return b.location === l; });
        return '<div class="list-item row"><div class="grow">📍 ' + esc(l) + '</div>' +
          '<button class="icon-btn" data-action="loc-rename" data-i="' + i + '">✏️</button>' +
          (usedL || s.locations.length <= 1 ? '<span class="muted" style="width:44px;text-align:center">—</span>'
            : '<button class="icon-btn" data-action="loc-del" data-i="' + i + '">🗑</button>') + '</div>';
      }).join('') + '<div class="list-item"><button class="btn small" data-action="loc-add">＋ Ajouter un emplacement</button></div>' : '') +
      '</div>';
    html += '<h2>Sauvegarde</h2><div class="card pad">' +
      '<p style="margin-top:0">Tes données sont enregistrées uniquement sur cet iPad, dans Safari. ' +
      '<b>Ne vide pas l\'historique / les données de sites de Safari</b>, et exporte une sauvegarde de temps en temps.</p>' +
      '<p class="muted">' + plural(productsInStock().length, 'produit') + ' en stock · ' + plural(db.recipes.length, 'recette') + '</p>' +
      '<div class="wrap"><button class="btn primary" data-action="export">Exporter</button>' +
      '<button class="btn" data-action="import">Importer</button></div></div>';
    var pending = db.products.filter(function (p) { return p.pending; }).length;
    html += '<h2>Base de produits</h2><div class="card pad">' +
      (localDb.map ? plural(localDb.count, 'produit') + ' courants reconnus même sans internet.'
        : 'Base hors ligne en cours de chargement…') +
      (pending ? '<div class="muted" style="margin-top:6px">' + plural(pending, 'fiche') + ' à compléter à la prochaine connexion.</div>' : '') +
      '</div>';
    html += '<h2>À propos</h2><div class="card pad muted">Stock Alimentaire — version légère compatible iPad iOS 12.<br>' +
      'Infos produits : Open Food Facts (openfoodfacts.org), base libre et collaborative.</div>';
    return html;
  }

  // ======================================================================
  // Actions (un seul écouteur pour tous les boutons)
  // ======================================================================
  var ACTIONS = {
    'tab': function (el) {
      ui.tab = el.getAttribute('data-tab');
      if (ui.tab !== 'recipes') ui.recipeId = null;
      render();
      window.scrollTo(0, 0);
    },
    'modal-close': function () { closeModal(); },
    'toast-undo': function () { var f = undoFn; hideToast(); if (f) f(); },

    // stock
    'sort': function () { ui.sort = ui.sort === 'expiry' ? 'name' : 'expiry'; render(); },
    'cat': function (el) { ui.category = el.getAttribute('data-cat') || null; render(); },
    'toggle': function (el) { var id = el.getAttribute('data-id'); ui.expanded[id] = !ui.expanded[id]; render(); },
    'use': function (el) {
      var p = productById(el.getAttribute('data-id'));
      useProduct(p.id, p.unit === 'pièce' ? 1 : null);
    },
    'use-ask': function (el) { useProduct(el.getAttribute('data-id'), null); },
    'add-manual': function () { openArticleForm({}); },
    'add-lot': function (el) { openArticleForm({ product: productById(el.getAttribute('data-id')) }); },
    'prod-edit': function (el) { openProductEdit(el.getAttribute('data-id')); },
    'prod-clear': function (el) {
      var p = productById(el.getAttribute('data-id'));
      var snap = snapshot();
      var o = {};
      batchesOf(p.id).forEach(function (b) { o[b.id] = 0; });
      applyQuantities(o);
      commitWithUndo(p.name + ' retiré du stock', snap);
    },
    'lot-edit': function (el) { openLotEdit(el.getAttribute('data-id')); },
    'lot-del': function (el) {
      var b = find(db.batches, el.getAttribute('data-id'));
      var p = productById(b.productId);
      var snap = snapshot();
      applyQuantities(makeObj(b.id, 0));
      commitWithUndo('Lot de ' + p.name + ' supprimé', snap);
    },

    // scanner
    'scan-open': openScanner,
    'scan-close': closeScanner,
    'scan-type': function () { askBarcode(!$('scanner').className); },

    // bientôt périmés
    'exp-use': function (el) {
      var b = find(db.batches, el.getAttribute('data-id'));
      var p = productById(b.productId);
      function go(q) {
        var snap = snapshot();
        applyQuantities(makeObj(b.id, Math.max(0, b.qty - q)));
        commitWithUndo(p.name + ' : ' + qty(Math.min(q, b.qty), p.unit) + ' en moins', snap);
      }
      if (p.unit === 'pièce' && b.qty <= 1) go(b.qty);
      else askQuantity('Quantité de « ' + p.name + ' » utilisée', p.unit, b.qty, b.qty, go);
    },
    'exp-trash': function (el) {
      var b = find(db.batches, el.getAttribute('data-id'));
      var p = productById(b.productId);
      var snap = snapshot();
      applyQuantities(makeObj(b.id, 0));
      commitWithUndo(p.name + ' retiré du stock', snap);
    },

    // recettes
    'recipe-new': function () { openRecipeForm(null); },
    'recipe-open': function (el) { ui.recipeId = el.getAttribute('data-id'); render(); window.scrollTo(0, 0); },
    'recipe-back': function () { ui.recipeId = null; render(); },
    'recipe-edit': function (el) { openRecipeForm(el.getAttribute('data-id')); },
    'recipe-plan': function (el) { planRecipe(recipeById(el.getAttribute('data-id'))); },
    'recipe-cook': function (el) {
      var r = recipeById(el.getAttribute('data-id'));
      cookRecipe(r, null, ui.people[r.id] || r.servings || null);
    },
    'r-people': function (el) {
      var r = recipeById(el.getAttribute('data-id'));
      var n = (ui.people[r.id] || r.servings || 1) + Number(el.getAttribute('data-delta'));
      ui.people[r.id] = Math.max(1, Math.min(50, n));
      render();
    },
    'plan-people': function (el) {
      var e = find(db.plan, el.getAttribute('data-id'));
      var r = recipeById(e.recipeId);
      askQuantity('Pour combien de personnes ?', 'personnes', e.people || r.servings || 2, null, function (n) {
        e.people = Math.max(1, Math.round(n));
        commit();
      });
    },
    'recipe-del': function (el) {
      var r = recipeById(el.getAttribute('data-id'));
      askConfirm('Supprimer la recette ?', '« ' + r.name + ' » sera aussi retirée du planning.', 'Supprimer', function () {
        var snap = snapshot();
        db.recipes = db.recipes.filter(function (x) { return x.id !== r.id; });
        db.plan = db.plan.filter(function (e) { return e.recipeId !== r.id; });
        ui.recipeId = null;
        commitWithUndo('Recette supprimée', snap);
      });
    },

    // planning
    'plan-mode': function (el) { db.settings.planByDay = el.getAttribute('data-mode') === 'day'; commit(); },
    'week': function (el) { ui.weekStart = L.addDays(ui.weekStart, Number(el.getAttribute('data-delta'))); render(); },
    'plan-add': function (el) {
      var day = el.getAttribute('data-day') || null;
      pickRecipe('Choisir une recette', function (r) {
        db.plan.push({ id: newId(), recipeId: r.id, date: day, done: false, people: r.servings || null });
        commit();
      });
    },
    'plan-open': function (el) { ui.tab = 'recipes'; ui.recipeId = el.getAttribute('data-id'); render(); window.scrollTo(0, 0); },
    'plan-done': function (el) {
      var e = find(db.plan, el.getAttribute('data-id'));
      cookRecipe(recipeById(e.recipeId), e);
    },
    'plan-del': function (el) {
      var id = el.getAttribute('data-id');
      db.plan = db.plan.filter(function (e) { return e.id !== id; });
      commit();
    },
    'plan-cleardone': function () { db.plan = db.plan.filter(function (e) { return !e.done; }); commit(); },

    // courses
    'shop-add': function () {
      var n = $('s-name').value.trim();
      if (!n) { $('s-name').focus(); return; }
      var q = L.parseNumber($('s-qty').value);
      db.shopping.push({ id: newId(), name: n, qty: q, unit: q === null ? null : $('s-unit').value, checked: false, auto: false });
      commit();
      setTimeout(function () { var i = $('s-name'); if (i) i.focus(); }, 30);
    },
    'shop-check': function (el, ev) {
      var i = find(db.shopping, el.getAttribute('data-id'));
      i.checked = !i.checked;
      if (ev && ev.target && ev.target.type === 'checkbox') ev.target.checked = i.checked;
      commit();
      // Article acheté : proposer de le ranger dans le stock (sans obligation).
      if (i.checked) showToast(i.name + ' acheté', function () { shoppingToStock(i.id); }, 'Ajouter au stock');
    },
    'shop-stock': function (el) { shoppingToStock(el.getAttribute('data-id')); },
    'shop-del': function (el) {
      var id = el.getAttribute('data-id');
      db.shopping = db.shopping.filter(function (i) { return i.id !== id; });
      commit();
    },
    'shop-clear': function () { db.shopping = db.shopping.filter(function (i) { return !i.checked; }); commit(); },

    // réglages
    'alert': function (el) {
      var v = db.settings.alertDays + Number(el.getAttribute('data-delta'));
      db.settings.alertDays = Math.max(0, Math.min(30, v));
      commit();
    },
    'cat-add': function () {
      askText('Nouvelle catégorie', '', function (n) {
        if (db.settings.categories.indexOf(n) >= 0) { showToast('Cette catégorie existe déjà'); return; }
        db.settings.categories.push(n);
        commit();
      });
    },
    'cat-rename': function (el) {
      var i = Number(el.getAttribute('data-i'));
      var old = db.settings.categories[i];
      askText('Renommer la catégorie', old, function (n) {
        if (n === old) return;
        if (db.settings.categories.indexOf(n) >= 0) { showToast('Cette catégorie existe déjà'); return; }
        db.settings.categories[i] = n;
        db.products.forEach(function (p) { if (p.category === old) p.category = n; });
        if (ui.category === old) ui.category = n;
        commit();
      });
    },
    'cat-del': function (el) { db.settings.categories.splice(Number(el.getAttribute('data-i')), 1); commit(); },
    'loc': function (el) { ui.location = el.getAttribute('data-loc') || null; render(); },
    'loc-toggle': function (el, ev) {
      db.settings.useLocations = !db.settings.useLocations;
      if (ev && ev.target && ev.target.type === 'checkbox') ev.target.checked = db.settings.useLocations;
      ui.location = null;
      commit();
    },
    'loc-add': function () {
      askText('Nouvel emplacement', '', function (n) {
        if (db.settings.locations.indexOf(n) >= 0) return;
        db.settings.locations.push(n);
        commit();
      });
    },
    'loc-rename': function (el) {
      var i = Number(el.getAttribute('data-i'));
      var old = db.settings.locations[i];
      askText("Renommer l'emplacement", old, function (n) {
        if (n === old || db.settings.locations.indexOf(n) >= 0) return;
        db.settings.locations[i] = n;
        db.batches.forEach(function (b) { if (b.location === old) b.location = n; });
        if (ui.location === old) ui.location = n;
        commit();
      });
    },
    'loc-del': function (el) { db.settings.locations.splice(Number(el.getAttribute('data-i')), 1); commit(); },
    'f-usedate': function (el) {
      $('f-date').value = el.getAttribute('data-key');
      $('f-ocr').innerHTML = '✅ Date reprise : ' + esc(fmtDate(el.getAttribute('data-key')));
    },
    'export': openExport,
    'import': openImport
  };

  document.addEventListener('click', function (ev) {
    var el = ev.target.closest ? ev.target.closest('[data-action]') : null;
    if (!el) {
      // clic sur le fond de la fenêtre : on la ferme
      if (ev.target === $('modal')) closeModal();
      return;
    }
    var name = el.getAttribute('data-action');
    var fn = modalHandlers[name] || ACTIONS[name];
    if (!fn) return;
    if (el.tagName !== 'INPUT') ev.preventDefault();
    fn(el, ev);
  });

  // Champs qui réagissent à la frappe
  document.addEventListener('input', function (ev) {
    var t = ev.target;
    if (t.id === 'search') {
      ui.search = t.value;
      var box = $('stock-list');
      if (box) box.innerHTML = stockListHtml();
    } else if (t.id === 'f-name') {
      updateFormHint();
      if (form && !form.photo && !form.photoUrl) $('f-photo-prev').innerHTML = thumb({ name: t.value }, true);
    }
  });

  document.addEventListener('change', function (ev) {
    var t = ev.target;
    if (t.id === 'f-photo' && t.files && t.files[0]) {
      resizePhoto(t.files[0], function (data) {
        if (!data || !form) { showToast('Photo illisible'); return; }
        form.photo = data;
        var nameEl = $('f-name') || $('p-name') || $('r-name');
        $('f-photo-prev').innerHTML = thumb({ name: nameEl ? nameEl.value : '', photo: data }, true);
      });
    } else if ((t.id === 'f-frozen' || t.id === 'f-cat') && $('f-loc')) {
      $('f-loc').value = defaultLocation($('f-cat').value, $('f-frozen').checked);
    } else if (t.id === 'f-ocr-file' && t.files && t.files[0]) {
      readDateFromPhoto(t.files[0]);
      t.value = '';
    } else if (t.id === 'i-file' && t.files && t.files[0]) {
      var reader = new FileReader();
      reader.onload = function () { $('i-text').value = reader.result; };
      reader.readAsText(t.files[0]);
    }
  });

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== 'Enter' || !ev.target || ev.target.tagName !== 'INPUT') return;
    var id = ev.target.id;
    if (id === 's-name' || id === 's-qty') { ev.preventDefault(); ACTIONS['shop-add'](); }
    else if ((id === 'm-text' || id === 'm-qty' || id === 'm-code') && modalHandlers['m-ok']) { ev.preventDefault(); modalHandlers['m-ok'](); }
  });

  // Recalcule les dates (« dans 3 jours ») quand on revient sur l'appli un autre jour.
  var lastDay = L.todayKey();
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && L.todayKey() !== lastDay) { lastDay = L.todayKey(); render(); }
  });

  syncShopping();
  render();

  // Base hors ligne chargée en avance (scan instantané) ; fiches à compléter dès qu'il y a internet.
  setTimeout(function () { loadLocalDb().then(function () { if (ui.tab === 'settings') render(); }); }, 1500);
  setTimeout(completePending, 3000);
  window.addEventListener('online', function () { setTimeout(completePending, 2000); });

  // Mode hors ligne : l'appli se garde une copie d'elle-même sur l'iPad.
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').catch(function () { /* hors ligne indisponible */ });
    });
  }
})();
