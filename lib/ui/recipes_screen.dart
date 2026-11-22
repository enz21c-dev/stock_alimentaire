import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import 'common.dart';

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final recipes = state.recipes.values.toList()
      ..sort((a, b) => normalizeName(a.name).compareTo(normalizeName(b.name)));
    return Scaffold(
      appBar: AppBar(title: const Text('Recettes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'recipe',
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle recette'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeEditScreen())),
      ),
      body: recipes.isEmpty
          ? const EmptyState(icon: Icons.menu_book, text: 'Aucune recette pour le moment.\nAjoute ta première recette !')
          : MaxWidth(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                itemCount: recipes.length,
                itemBuilder: (_, i) {
                  final r = recipes[i];
                  final missing = recipeMissing(state, r);
                  return Card(
                    child: ListTile(
                      leading: ProductAvatar(photoData: r.photoData, name: r.name),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${r.ingredients.length} ingrédient${r.ingredients.length > 1 ? 's' : ''}'
                        '${r.ingredients.isEmpty ? '' : missing == 0 ? ' · tout est en stock' : ' · $missing manquant${missing > 1 ? 's' : ''}'}',
                      ),
                      trailing: Icon(
                        missing == 0 ? Icons.check_circle : Icons.shopping_basket_outlined,
                        color: missing == 0 ? statusColor(ExpiryStatus.ok) : Theme.of(context).colorScheme.outline,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id)),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Nombre d'ingrédients manquants ou insuffisants pour faire la recette une fois.
int recipeMissing(AppState state, Recipe r) => computeNeeds(
      plan: [MealPlanEntry(recipeId: r.id)],
      recipes: {r.id: r},
      products: state.products.values.toList(),
      batches: state.batches.values.toList(),
    ).where((n) => n.isMissing).length;

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});
  final String recipeId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = state.recipes[recipeId];
    if (r == null) return const Scaffold();
    final products = state.products.values.toList();

    return Scaffold(
      appBar: AppBar(title: Text(r.name), actions: [
        IconButton(
          tooltip: 'Modifier',
          icon: const Icon(Icons.edit),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: r))),
        ),
        IconButton(
          tooltip: 'Supprimer',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, 'Supprimer la recette ?', '« ${r.name} » sera aussi retirée du planning.',
                ok: 'Supprimer')) {
              await state.deleteRecipe(r.id);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
      body: MaxWidth(
        width: 760,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (r.photoData != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(decodePhoto(r.photoData!), height: 220, fit: BoxFit.cover),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: const Text('Planifier'),
              onPressed: () => addToPlan(context, r),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.soup_kitchen),
              label: const Text("Je l'ai cuisinée"),
              onPressed: () => cookRecipe(context, r),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Ingrédients', style: Theme.of(context).textTheme.titleLarge),
          if (r.ingredients.isEmpty) const Text('Aucun ingrédient.'),
          for (final ing in r.ingredients)
            Builder(builder: (context) {
              final p = matchProduct(ing, products);
              final base = baseUnit(ing.unit);
              final ok = p != null &&
                  availableQuantity(p, state.batches.values.toList(), base) + 1e-9 >=
                      convert(ing.quantity, ing.unit, base)!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(ok ? Icons.check_circle : Icons.cancel_outlined,
                    color: ok ? statusColor(ExpiryStatus.ok) : statusColor(ExpiryStatus.expired)),
                title: Text('${formatQty(ing.quantity, ing.unit)} — ${ing.name}'),
                subtitle: Text(p == null
                    ? 'Pas dans le stock'
                    : 'En stock : ${formatQty(availableQuantity(p, state.batches.values.toList(), p.unit), p.unit)} (${p.name})'),
              );
            }),
          const SizedBox(height: 16),
          Text('Préparation', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(r.instructions.isEmpty ? '—' : r.instructions, style: const TextStyle(fontSize: 16, height: 1.4)),
        ]),
      ),
    );
  }
}

/// Ajoute une recette au planning (jour précis ou liste libre selon le mode).
Future<void> addToPlan(BuildContext context, Recipe r) async {
  final state = AppScope.read(context);
  if (!state.settings.planByDay) {
    await state.savePlanEntry(MealPlanEntry(recipeId: r.id));
    await state.refreshShoppingFromPlan();
    if (context.mounted) showMessage(context, '« ${r.name} » ajoutée au planning');
    return;
  }
  final today = dateOnly(DateTime.now());
  final day = await showDialog<DateTime>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text('Planifier « ${r.name} »'),
      children: [
        for (var i = 0; i < 8; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, today.add(Duration(days: i))),
            child: Text(i == 0
                ? "Aujourd'hui"
                : i == 1
                    ? 'Demain'
                    : formatDay(today.add(Duration(days: i)))),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final d = await showDatePicker(
              context: c,
              initialDate: today,
              firstDate: today.subtract(const Duration(days: 30)),
              lastDate: today.add(const Duration(days: 365)),
            );
            if (c.mounted) Navigator.pop(c, d);
          },
          child: const Text('Autre date…'),
        ),
      ],
    ),
  );
  if (day == null) return;
  await state.savePlanEntry(MealPlanEntry(recipeId: r.id, date: day));
  await state.refreshShoppingFromPlan();
  if (context.mounted) showMessage(context, '« ${r.name} » prévue le ${formatDay(day).toLowerCase()}');
}

/// Valide une recette cuisinée : propose (sans jamais l'imposer) de retirer
/// ses ingrédients du stock. [entry] = l'entrée du planning à marquer « faite ».
Future<void> cookRecipe(BuildContext context, Recipe r, {MealPlanEntry? entry}) async {
  final state = AppScope.read(context);
  final products = state.products.values.toList();
  final lines = <Widget>[];
  var anyInStock = false;
  for (final ing in r.ingredients) {
    final p = matchProduct(ing, products);
    final inStock = p != null && state.totalOf(p.id) > 0 && convert(ing.quantity, ing.unit, p.unit) != null;
    anyInStock |= inStock;
    if (!inStock) {
      lines.add(Text('• ${ing.name} : pas en stock (ignoré)'));
      continue;
    }
    final total = state.totalOf(p.id);
    final wanted = convert(ing.quantity, ing.unit, p.unit)!;
    lines.add(Text(wanted <= total + 1e-9
        ? '• ${formatQty(ing.quantity, ing.unit)} de ${p.name}'
        : '• ${p.name} : tout le stock (${formatQty(total, p.unit)}, il en fallait ${formatQty(ing.quantity, ing.unit)})'));
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('« ${r.name} » est faite ?'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(anyInStock ? 'Retirer ces quantités du stock ?' : 'Aucun ingrédient de cette recette n\'est en stock.'),
          const SizedBox(height: 8),
          ...lines,
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(c, 'keep'), child: const Text('Ne rien retirer')),
        if (anyInStock)
          FilledButton(onPressed: () => Navigator.pop(c, 'consume'), child: const Text('Retirer du stock')),
      ],
    ),
  );
  if (choice == null) return;
  if (entry != null) {
    entry.done = true;
    await state.savePlanEntry(entry);
  }
  if (choice == 'consume') {
    final snap = await state.consumeRecipe(r);
    if (entry != null) {
      // L'annulation remet aussi la recette « à faire ».
      await state.refreshShoppingFromPlan();
    }
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('Stock mis à jour pour « ${r.name} »'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            await state.undo(snap);
            if (entry != null) {
              entry.done = false;
              await state.savePlanEntry(entry);
            }
          },
        ),
      ));
    }
  } else {
    if (entry != null) await state.refreshShoppingFromPlan();
    if (context.mounted) showMessage(context, '« ${r.name} » marquée comme faite');
  }
}

/// Création / modification d'une recette.
class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _IngRow {
  final TextEditingController name;
  final TextEditingController qty;
  final FocusNode focus = FocusNode();
  String unit;
  String? productId;
  _IngRow({String name = '', double qty = 1, this.unit = 'pièce', this.productId})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: formatNumber(qty));
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  late final _name = TextEditingController(text: widget.recipe?.name ?? '');
  late final _instructions = TextEditingController(text: widget.recipe?.instructions ?? '');
  late String? _photo = widget.recipe?.photoData;
  late final List<_IngRow> _rows = [
    for (final i in widget.recipe?.ingredients ?? <RecipeIngredient>[])
      _IngRow(name: i.name, qty: i.quantity, unit: i.unit, productId: i.productId),
  ];
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _rows.add(_IngRow());
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.qty.dispose();
      r.focus.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppScope.read(context);
    final ings = <RecipeIngredient>[];
    for (final r in _rows) {
      final n = r.name.text.trim();
      if (n.isEmpty) continue;
      // Le lien vers un produit n'est gardé que si le nom n'a pas changé.
      final linked = r.productId == null ? null : state.products[r.productId];
      ings.add(RecipeIngredient(
        name: n,
        quantity: parseNumber(r.qty.text) ?? 1,
        unit: r.unit,
        productId: linked != null && linked.name == n ? linked.id : null,
      ));
    }
    final recipe = widget.recipe ?? Recipe(name: '');
    recipe
      ..name = _name.text.trim()
      ..ingredients = ings
      ..instructions = _instructions.text.trim()
      ..photoData = _photo;
    await state.saveRecipe(recipe);
    await state.refreshShoppingFromPlan();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final known = state.products.values.toList()
      ..sort((a, b) => normalizeName(a.name).compareTo(normalizeName(b.name)));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'Nouvelle recette' : 'Modifier la recette'),
        actions: [TextButton(onPressed: _save, child: const Text('Enregistrer'))],
      ),
      body: Form(
        key: _formKey,
        child: MaxWidth(
          width: 760,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              InkWell(
                onTap: () async {
                  final p = await pickPhoto(context);
                  if (p != null) setState(() => _photo = p);
                },
                child: _photo == null
                    ? Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined),
                      )
                    : ProductAvatar(photoData: _photo, name: '', size: 72),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom de la recette'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indique un nom' : null,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Text('Ingrédients', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Choisis un produit proposé pour le relier à ton stock, ou écris un nom libre.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final (i, row) in _rows.indexed)
              Padding(
                key: ObjectKey(row),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 5,
                    child: Autocomplete<Product>(
                      textEditingController: row.name,
                      focusNode: row.focus,
                      displayStringForOption: (p) => p.name,
                      optionsBuilder: (v) {
                        final q = normalizeName(v.text);
                        if (q.isEmpty) return const [];
                        return known.where((p) => normalizeName(p.name).contains(q)).take(8);
                      },
                      onSelected: (p) => setState(() {
                        row.productId = p.id;
                        if (baseUnit(row.unit) != baseUnit(p.unit)) row.unit = p.unit;
                      }),
                      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
                        controller: ctrl,
                        focusNode: focus,
                        decoration: InputDecoration(
                          labelText: 'Ingrédient ${i + 1}',
                          isDense: true,
                          suffixIcon: row.productId != null && state.products[row.productId]?.name == ctrl.text
                              ? const Icon(Icons.link, size: 18)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: row.qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Qté', isDense: true),
                      validator: (v) => row.name.text.trim().isEmpty || (parseNumber(v ?? '') ?? 0) > 0 ? null : '?',
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: DropdownButtonFormField<String>(
                      initialValue: row.unit,
                      isDense: true,
                      items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                      onChanged: (v) => setState(() => row.unit = v!),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _rows.removeAt(i)),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un ingrédient'),
                onPressed: () => setState(() => _rows.add(_IngRow())),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructions,
              minLines: 5,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Préparation',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Enregistrer la recette')),
          ]),
        ),
      ),
    );
  }
}
