import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import '../services/date_reader.dart';
import '../services/open_food_facts.dart';
import 'common.dart';

/// Écran plein d'ajout manuel (ou d'ajout d'un lot à un produit existant,
/// ou d'un article acheté depuis la liste de courses).
class AddArticleScreen extends StatelessWidget {
  const AddArticleScreen({super.key, this.product, this.prefillName, this.prefillQty, this.prefillUnit, this.onAdded});
  final Product? product;
  final String? prefillName;
  final double? prefillQty;
  final String? prefillUnit;
  final VoidCallback? onAdded;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(product == null ? 'Ajouter un article' : 'Ajouter un lot')),
        body: MaxWidth(
          width: 640,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ArticleForm(
              product: product,
              prefillName: prefillName,
              prefillQty: prefillQty,
              prefillUnit: prefillUnit,
              onSaved: () {
                onAdded?.call();
                showMessage(context, 'Article ajouté au stock');
                Navigator.pop(context);
              },
            ),
          ),
        ),
      );
}

/// Formulaire d'ajout d'un lot. Pré-rempli avec un produit déjà connu, ou
/// avec les infos Open Food Facts, ou vide (saisie manuelle).
class ArticleForm extends StatefulWidget {
  const ArticleForm({
    super.key,
    this.product,
    this.off,
    this.barcode,
    required this.onSaved,
    this.saveLabel = 'Ajouter au stock',
    this.prefillName,
    this.prefillQty,
    this.prefillUnit,
  });

  final Product? product;
  final OffProduct? off;
  final String? barcode;
  final VoidCallback onSaved;
  final String saveLabel;
  final String? prefillName;
  final double? prefillQty;
  final String? prefillUnit;

  @override
  State<ArticleForm> createState() => _ArticleFormState();
}

class _ArticleFormState extends State<ArticleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  final _qty = TextEditingController(text: '1');
  final _kcal = TextEditingController();
  late String _category;
  String _unit = 'pièce';
  String? _photoData;
  String? _photoUrl;
  DateTime _date = dateOnly(DateTime.now()).add(const Duration(days: 7));
  bool _saving = false;
  bool _frozen = false;
  String? _location;
  bool _reading = false;
  String? _ocrMessage;
  List<FoundDate> _ocrDates = const [];

  /// Produit existant qui sera réutilisé (pour verrouiller l'unité).
  Product? _existing;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final off = widget.off;
    _name = TextEditingController(text: p?.name ?? off?.name ?? widget.prefillName ?? '');
    _brand = TextEditingController(text: p?.brand ?? off?.brand ?? '');
    _category = p?.category ?? off?.category ?? 'Autre';
    _unit = p?.unit ?? 'pièce';
    _photoData = p?.photoData;
    _photoUrl = p?.photoUrl ?? off?.imageUrl;
    _existing = p;
    // Quantité proposée d'après l'emballage : « 4 x 125 g » → 4 pièces, « 400 g » → 400 g.
    var (q, u) = (1.0, _unit);
    if (p != null && p.unit != 'pièce' && p.packQty != null && p.packUnit != null) {
      final c = convert(p.packQty!, p.packUnit!, p.unit);
      if (c != null) (q, u) = (c, p.unit);
    } else if (p == null && off?.pack != null) {
      (q, u) = suggestQuantity(off!.pack);
    }
    if (widget.prefillQty != null) {
      final pu = widget.prefillUnit ?? 'pièce';
      final c = p == null ? null : convert(widget.prefillQty!, pu, p.unit);
      (q, u) = c != null ? (c, p!.unit) : (widget.prefillQty!, pu);
    }
    _qty.text = formatNumber(q);
    _unit = u;
    final k = p?.kcal100 ?? off?.kcal100;
    if (k != null) _kcal.text = formatNumber(k);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.read(context);
    if (widget.product == null) _category = state.mapCategory(_category);
    final cats = state.settings.categories;
    if (!cats.contains(_category)) _category = state.mapCategory('Autre');
    _location ??= state.settings.useLocations ? state.defaultLocation(_category) : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _qty.dispose();
    _kcal.dispose();
    super.dispose();
  }

  void _onNameChanged(String v) {
    if (widget.product != null) return;
    final state = AppScope.read(context);
    final match = state.productByName(v);
    setState(() {
      _existing = match;
      if (match != null) {
        _category = match.category;
        if (state.totalOf(match.id) > 0) _unit = match.unit;
        _photoData ??= match.photoData;
        _photoUrl ??= match.photoUrl;
        if (_kcal.text.isEmpty && match.kcal100 != null) _kcal.text = formatNumber(match.kcal100!);
      }
    });
  }

  void _updateLocation() {
    final state = AppScope.read(context);
    if (state.settings.useLocations) _location = state.defaultLocation(_category, frozen: _frozen);
  }

  /// Photo de l'endroit où la date est imprimée → dates réellement lues.
  Future<void> _readDate() async {
    setState(() {
      _reading = true;
      _ocrMessage = 'Lecture de la photo…';
      _ocrDates = const [];
    });
    final result = await DateReader.readFromCamera();
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (result == null) {
        _ocrMessage = null;
      } else if (result.error != null) {
        _ocrMessage = result.error;
      } else if (result.dates.isEmpty) {
        _ocrMessage =
            'Aucune date lisible sur cette photo. Rapproche-toi de la date (bien nette, sans reflet) ou saisis-la à la main.';
      } else {
        _ocrDates = result.dates;
        _ocrMessage = '${result.dates.length == 1 ? 'Date lue sur la photo' : 'Plusieurs dates lues — choisis la bonne'} '
            '(« ${result.dates.map((d) => d.text).join(' / ')} »). Vérifie avant de valider.';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final kcal = parseNumber(_kcal.text);
    final pack = widget.off?.pack;
    await state.addStock(
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: widget.barcode ?? widget.product?.barcode,
      category: _category,
      unit: _unit,
      photoUrl: _photoUrl,
      photoData: _photoData,
      quantity: parseNumber(_qty.text)!,
      expiration: _date,
      kcal100: kcal != null && kcal >= 0 ? kcal : null,
      packQty: pack?.each,
      packUnit: pack?.unit,
      frozen: _frozen,
      location: _location,
    );
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final categories = state.settings.categories;
    // Si le produit existe déjà avec du stock, on reste dans une unité compatible.
    final locked = _existing != null && state.totalOf(_existing!.id) > 0;
    final allowedUnits =
        locked ? units.where((u) => baseUnit(u) == baseUnit(_existing!.unit)).toList() : units;
    if (!allowedUnits.contains(_unit)) _unit = allowedUnits.first;
    final today = dateOnly(DateTime.now());
    final small = Theme.of(context).textTheme.bodySmall;

    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.off?.local ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text("Trouvé dans la base de produits de l'appli (sans internet).",
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final p = await pickPhoto(context);
              if (p != null) setState(() => _photoData = p);
            },
            child: Stack(children: [
              ProductAvatar(photoData: _photoData, photoUrl: _photoUrl, name: _name.text, size: 88),
              const Positioned(
                right: 4,
                bottom: 4,
                child: CircleAvatar(radius: 14, child: Icon(Icons.photo_camera, size: 16)),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(children: [
              TextFormField(
                controller: _name,
                enabled: widget.product == null,
                decoration: const InputDecoration(labelText: 'Nom du produit'),
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onNameChanged,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Indique un nom' : null,
              ),
              TextFormField(
                controller: _brand,
                enabled: widget.product == null,
                decoration: const InputDecoration(labelText: 'Marque (facultatif)'),
              ),
            ]),
          ),
        ]),
        if (widget.barcode != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Code-barres : ${widget.barcode}', style: small),
          ),
        if (widget.off?.quantityText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Contenance indiquée : ${widget.off!.quantityText}', style: small),
          ),
        if (_existing != null && widget.product == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Déjà connu : un nouveau lot sera ajouté à « ${_existing!.name} ».',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
          items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() {
            _category = v!;
            _updateLocation();
          }),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder()),
              validator: (v) {
                final n = parseNumber(v ?? '');
                if (n == null) return 'Nombre invalide';
                if (n <= 0) return 'Doit être > 0';
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('${allowedUnits.join()}$_unit'),
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unité', border: OutlineInputBorder()),
              items: [for (final u in allowedUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => _unit = v!),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextFormField(
          controller: _kcal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Calories pour 100 g ou 100 ml (facultatif)',
            hintText: 'ex. 250',
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _frozen,
          title: const Text('❄️ Je le mets au congélateur (la date ne comptera plus)'),
          onChanged: (v) => setState(() {
            _frozen = v ?? false;
            _updateLocation();
          }),
        ),
        if (state.settings.useLocations) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('loc$_location'),
            initialValue: state.settings.locations.contains(_location) ? _location : null,
            decoration: const InputDecoration(labelText: 'Emplacement', border: OutlineInputBorder()),
            items: [for (final l in state.settings.locations) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => _location = v),
          ),
          const SizedBox(height: 16),
        ],
        Text('À consommer avant le', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(formatDate(_date), style: const TextStyle(fontSize: 16)),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: today.subtract(const Duration(days: 365)),
              lastDate: today.add(const Duration(days: 365 * 10)),
            );
            if (d != null) setState(() => _date = dateOnly(d));
          },
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final (label, days) in [('+3 j', 3), ('+1 sem.', 7), ('+2 sem.', 14), ('+1 mois', 30), ('+6 mois', 182), ('+1 an', 365)])
            ActionChip(label: Text(label), onPressed: () => setState(() => _date = today.add(Duration(days: days)))),
        ]),
        if (DateReader.available) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: _reading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: const Text("Lire la date sur l'emballage"),
              onPressed: _reading ? null : _readDate,
            ),
          ),
          if (_ocrMessage != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_ocrMessage!, style: small)),
          if (_ocrDates.isNotEmpty)
            Wrap(spacing: 8, children: [
              for (final d in _ocrDates)
                FilledButton.tonal(
                  onPressed: () => setState(() {
                    _date = d.date;
                    _ocrMessage = '✅ Date reprise : ${formatDate(d.date)}';
                    _ocrDates = const [];
                  }),
                  child: Text('${formatDate(d.date)}${d.monthOnly ? ' (fin du mois)' : ''}'),
                ),
            ]),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(widget.saveLabel),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
        ),
      ]),
    );
  }
}

/// Modifier les infos d'un produit (nom, marque, catégorie, photo, calories,
/// poids d'une pièce, stock minimum).
class EditProductScreen extends StatefulWidget {
  const EditProductScreen({super.key, required this.product});
  final Product product;

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _brand = TextEditingController(text: widget.product.brand ?? '');
  late final _kcal =
      TextEditingController(text: widget.product.kcal100 == null ? '' : formatNumber(widget.product.kcal100!));
  late final _pack =
      TextEditingController(text: widget.product.packQty == null ? '' : formatNumber(widget.product.packQty!));
  late final _min =
      TextEditingController(text: widget.product.minQty == null ? '' : formatNumber(widget.product.minQty!));
  late String _packUnit = baseUnit(widget.product.packUnit ?? 'g') == 'ml' ? 'ml' : 'g';
  late String _category = widget.product.category;
  late String? _photoData = widget.product.photoData;
  late String? _photoUrl = widget.product.photoUrl;

  @override
  void dispose() {
    for (final c in [_name, _brand, _kcal, _pack, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cats = {...state.settings.categories, _category}.toList();
    final p0 = widget.product;
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le produit')),
      body: MaxWidth(
        width: 640,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: InkWell(
              onTap: () async {
                final p = await pickPhoto(context);
                if (p != null) setState(() => _photoData = p);
              },
              child: ProductAvatar(photoData: _photoData, photoUrl: _photoUrl, name: _name.text, size: 120),
            ),
          ),
          if (_photoData != null || _photoUrl != null)
            TextButton(
              onPressed: () => setState(() {
                _photoData = null;
                _photoUrl = null;
              }),
              child: const Text('Retirer la photo'),
            ),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom')),
          TextField(controller: _brand, decoration: const InputDecoration(labelText: 'Marque')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
            items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _kcal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Calories pour 100 g ou 100 ml', hintText: 'inconnu'),
          ),
          if (p0.unit == 'pièce')
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pack,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: "Poids ou volume d'une pièce (pour les calories)", hintText: 'ex. 125'),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _packUnit,
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('g')),
                  DropdownMenuItem(value: 'ml', child: Text('ml')),
                ],
                onChanged: (v) => setState(() => _packUnit = v!),
              ),
            ]),
          TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Toujours en avoir au moins (${p0.unit})',
              helperText: 'En dessous, le produit est ajouté à la liste de courses',
              hintText: 'pas de minimum',
            ),
          ),
          if (p0.barcode != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Code-barres : ${p0.barcode}')),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Unité : ${p0.unit}')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (_name.text.trim().isEmpty) return;
              final k = parseNumber(_kcal.text);
              final w = parseNumber(_pack.text);
              final m = parseNumber(_min.text);
              final p = widget.product
                ..name = _name.text.trim()
                ..brand = _brand.text.trim().isEmpty ? null : _brand.text.trim()
                ..category = _category
                ..photoData = _photoData
                ..photoUrl = _photoUrl
                ..kcal100 = (k != null && k >= 0) ? k : null
                ..minQty = (m != null && m > 0) ? m : null;
              if (p.unit == 'pièce') {
                p.packQty = (w != null && w > 0) ? w : null;
                p.packUnit = p.packQty == null ? null : _packUnit;
              }
              await state.saveProduct(p);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
