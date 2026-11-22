import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/units.dart';
import '../models/models.dart';
import '../services/open_food_facts.dart';
import 'common.dart';

/// Écran plein d'ajout manuel (ou d'ajout d'un lot à un produit existant).
class AddArticleScreen extends StatelessWidget {
  const AddArticleScreen({super.key, this.product});
  final Product? product;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(product == null ? 'Ajouter un article' : 'Ajouter un lot')),
        body: MaxWidth(
          width: 640,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ArticleForm(
              product: product,
              onSaved: () {
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
  });

  final Product? product;
  final OffProduct? off;
  final String? barcode;
  final VoidCallback onSaved;
  final String saveLabel;

  @override
  State<ArticleForm> createState() => _ArticleFormState();
}

class _ArticleFormState extends State<ArticleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  final _qty = TextEditingController(text: '1');
  late String _category;
  String _unit = 'pièce';
  String? _photoData;
  String? _photoUrl;
  DateTime _date = dateOnly(DateTime.now()).add(const Duration(days: 7));
  bool _saving = false;

  /// Produit existant qui sera réutilisé (pour verrouiller l'unité).
  Product? _existing;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final off = widget.off;
    _name = TextEditingController(text: p?.name ?? off?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? off?.brand ?? '');
    _category = p?.category ?? off?.category ?? 'Autre';
    _unit = p?.unit ?? 'pièce';
    _photoData = p?.photoData;
    _photoUrl = p?.photoUrl ?? off?.imageUrl;
    _existing = p;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cats = AppScope.read(context).settings.categories;
    if (!cats.contains(_category)) _category = cats.contains('Autre') ? 'Autre' : cats.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _qty.dispose();
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
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
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

    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            child: Text('Code-barres : ${widget.barcode}', style: Theme.of(context).textTheme.bodySmall),
          ),
        if (widget.off?.quantity != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Contenance indiquée : ${formatQty(widget.off!.quantity!, widget.off!.unit!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
          onChanged: (v) => setState(() => _category = v!),
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
              key: ValueKey(allowedUnits.join()),
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unité', border: OutlineInputBorder()),
              items: [for (final u in allowedUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => _unit = v!),
            ),
          ),
        ]),
        const SizedBox(height: 16),
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

/// Modifier les infos d'un produit (nom, marque, catégorie, photo).
class EditProductScreen extends StatefulWidget {
  const EditProductScreen({super.key, required this.product});
  final Product product;

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _brand = TextEditingController(text: widget.product.brand ?? '');
  late String _category = widget.product.category;
  late String? _photoData = widget.product.photoData;
  late String? _photoUrl = widget.product.photoUrl;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cats = {...state.settings.categories, _category}.toList();
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
          if (widget.product.barcode != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Code-barres : ${widget.product.barcode}'),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Unité : ${widget.product.unit}'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (_name.text.trim().isEmpty) return;
              final p = widget.product
                ..name = _name.text.trim()
                ..brand = _brand.text.trim().isEmpty ? null : _brand.text.trim()
                ..category = _category
                ..photoData = _photoData
                ..photoUrl = _photoUrl;
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
