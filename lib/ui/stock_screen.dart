import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import '../platform/platform.dart';
import 'add_article_screen.dart';
import 'common.dart';
import 'home_shell.dart';
import 'scan_screen.dart';

enum _Sort { expiry, name }

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _search = TextEditingController();
  String? _category; // null = toutes
  String? _location; // null = partout
  _Sort _sort = _Sort.expiry;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _chips(List<String?> values, String? selected, String Function(String?) label, void Function(String?) onTap) =>
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(label: Text(label(c)), selected: selected == c, onSelected: (_) => onTap(c)),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = normalizeName(_search.text);
    final useLoc = state.settings.useLocations;
    if (!useLoc) _location = null;

    final all = state.productsInStock;
    final categories = {for (final p in all) p.category}.toList()
      ..sort((a, b) => state.settings.categories.indexOf(a).compareTo(state.settings.categories.indexOf(b)));

    final products = all.where((p) {
      if (_category != null && p.category != _category) return false;
      if (_location != null && !state.batchesOf(p.id).any((b) => b.location == _location)) return false;
      if (q.isEmpty) return true;
      return normalizeName('${p.name} ${p.brand ?? ''}').contains(q);
    }).toList();
    // Tout congelé : en fin de liste.
    final nearest = {
      for (final p in products)
        p.id: state.batchesOf(p.id).first.frozen ? DateTime(9999) : state.batchesOf(p.id).first.expirationDate,
    };
    products.sort((a, b) => _sort == _Sort.name
        ? normalizeName(a.name).compareTo(normalizeName(b.name))
        : nearest[a.id]!.compareTo(nearest[b.id]!));

    final expiring = state.expiringBatches.length;
    final anyExpired = state.expiringBatches.any((b) => daysUntil(b.expirationDate) < 0);
    final bannerBg = anyExpired ? Theme.of(context).colorScheme.errorContainer : const Color(0xFFFFE0B2);
    final bannerFg = anyExpired ? Theme.of(context).colorScheme.onErrorContainer : const Color(0xFF5D3A00);
    final low = state.belowMin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon stock'),
        actions: [
          PopupMenuButton<_Sort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Trier',
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.expiry, child: Text('Par date de péremption')),
              PopupMenuItem(value: _Sort.name, child: Text('Par nom')),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'manual',
          tooltip: 'Ajouter à la main',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddArticleScreen())),
          child: const Icon(Icons.edit),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'scan',
          onPressed: () {
            unlockAudio();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
          },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scanner'),
        ),
      ]),
      body: MaxWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher un produit',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _search.clear())),
              ),
            ),
          ),
          if (categories.length > 1)
            _chips([null, ...categories], _category, (c) => c ?? 'Tout', (c) => setState(() => _category = c)),
          if (useLoc)
            _chips([null, ...state.settings.locations], _location, (c) => c ?? '📍 Partout',
                (c) => setState(() => _location = c)),
          if (low.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              color: const Color(0xFFFFE0B2),
              child: ListTile(
                leading: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF5D3A00)),
                title: Text(
                  'Sous le stock minimum : ${low.take(3).map((p) => p.name).join(', ')}${low.length > 3 ? '…' : ''}',
                  style: const TextStyle(color: Color(0xFF5D3A00)),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF5D3A00)),
                onTap: () => HomeShell.goTo(context, HomeShell.shopping),
              ),
            ),
          if (expiring > 0)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              color: bannerBg,
              child: ListTile(
                leading: Icon(Icons.warning_amber, color: bannerFg),
                title: Text(
                  expiring == 1
                      ? anyExpired ? '1 lot périmé ou à consommer vite' : '1 lot à consommer vite'
                      : anyExpired ? '$expiring lots périmés ou à consommer vite' : '$expiring lots à consommer vite',
                  style: TextStyle(color: bannerFg),
                ),
                trailing: Icon(Icons.chevron_right, color: bannerFg),
                onTap: () => HomeShell.goTo(context, HomeShell.expiring),
              ),
            ),
          Expanded(
            child: all.isEmpty
                ? const EmptyState(
                    icon: Icons.kitchen,
                    text: 'Ton stock est vide.\nAppuie sur « Scanner » pour ajouter tes premiers articles.',
                  )
                : products.isEmpty
                    ? const EmptyState(icon: Icons.search_off, text: 'Aucun produit ne correspond.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 140),
                        itemCount: products.length,
                        itemBuilder: (_, i) => ProductCard(product: products[i], key: ValueKey(products[i].id)),
                      ),
          ),
        ]),
      ),
    );
  }
}

/// « · 539 kcal/100 g » ou « · 75 kcal/pièce » (vide si inconnu).
String kcalInfo(Product p) {
  if (p.kcal100 == null) return '';
  if (p.unit == 'pièce') {
    final k = kcalOf(p, 1, 'pièce');
    return k == null ? '' : ' · ${kcalText(k)}/pièce';
  }
  return ' · ${kcalText(p.kcal100!)}/100 ${baseUnit(p.unit) == 'ml' ? 'ml' : 'g'}';
}

/// Un produit avec le total de ses lots ; se déplie pour voir chaque lot.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  Future<void> _use(BuildContext context, {double? quantity}) async {
    final state = AppScope.read(context);
    final total = state.totalOf(product.id);
    final q = quantity ??
        await askQuantity(context,
            title: 'Utiliser « ${product.name} »',
            unit: product.unit,
            initial: product.unit == 'pièce' ? 1 : total,
            max: total);
    if (q == null || !context.mounted) return;
    final snap = await state.consume(product.id, q);
    if (!context.mounted) return;
    final left = state.totalOf(product.id);
    showUndo(
      context,
      left <= 0
          ? '${product.name} : stock épuisé'
          : '${product.name} : ${formatQty(q > total ? total : q, product.unit)} en moins, reste ${formatQty(left, product.unit)}',
      snap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lots = state.batchesOf(product.id);
    final total = lots.fold(0.0, (s, b) => s + b.quantity);
    final first = lots.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        shape: const Border(),
        leading: ProductAvatar.of(product),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${formatQty(total, product.unit)} au total${lots.length > 1 ? ' · ${lots.length} lots' : ''}'
                '${kcalInfo(product)}'),
            LotTag(first, alertDays: state.settings.alertDays),
          ]),
        ),
        trailing: IconButton(
          tooltip: product.unit == 'pièce' ? 'Utiliser 1' : 'Utiliser…',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => _use(context, quantity: product.unit == 'pièce' ? 1 : null),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        children: [
          for (final b in lots) _BatchRow(product: product, batch: b),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.restaurant),
              label: const Text('Utiliser…'),
              onPressed: () => _use(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un lot'),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AddArticleScreen(product: product))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier le produit'),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductScreen(product: product))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Tout retirer'),
              onPressed: () async {
                final snap = await state.deleteAllBatches(product.id);
                if (context.mounted) showUndo(context, '${product.name} retiré du stock', snap);
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.product, required this.batch});
  final Product product;
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = daysUntil(batch.expirationDate);
    final loc = state.settings.useLocations ? ' · 📍 ${batch.location ?? 'emplacement ?'}' : '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: batch.frozen
          ? const Icon(Icons.ac_unit, color: Color(0xFF1E88E5), size: 16)
          : StatusDot(expiryStatus(days, alertDays: state.settings.alertDays)),
      title: Row(children: [
        Text(formatQty(batch.quantity, product.unit)),
        if (batch.opened && !batch.frozen) ...[const SizedBox(width: 8), const OpenedTag()],
      ]),
      subtitle: Text(batch.frozen
          ? '❄️ congelé${batch.frozenAt == null ? '' : ' le ${formatDate(batch.frozenAt!)}'} · la date ne compte pas$loc'
          : 'À consommer avant le ${formatDate(batch.expirationDate)} · ${expiryLabel(days)}$loc'),
      onTap: () => editLot(context, product, batch),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Modifier, entamé, congeler',
          icon: const Icon(Icons.more_horiz),
          onPressed: () => editLot(context, product, batch),
        ),
        IconButton(
          tooltip: 'Supprimer ce lot',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final snap = await state.deleteBatch(batch.id);
            if (context.mounted) showUndo(context, 'Lot de ${product.name} supprimé', snap);
          },
        ),
      ]),
    );
  }
}

/// Fiche d'un lot : quantité, date, entamé, congeler / décongeler, emplacement.
Future<void> editLot(BuildContext context, Product product, Batch batch) async {
  final state = AppScope.read(context);
  final qty = TextEditingController(text: formatNumber(batch.quantity));
  var date = batch.expirationDate;
  var opened = batch.opened;
  var location = batch.location ?? (state.settings.useLocations ? state.defaultLocation(product.category, frozen: batch.frozen) : null);
  final today = dateOnly(DateTime.now());
  final action = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text('Lot de ${product.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantité', suffixText: product.unit),
            ),
            if (state.settings.useLocations)
              DropdownButtonFormField<String>(
                initialValue: state.settings.locations.contains(location) ? location : null,
                decoration: const InputDecoration(labelText: 'Emplacement'),
                items: [for (final l in state.settings.locations) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => setD(() => location = v),
              ),
            const SizedBox(height: 8),
            if (batch.frozen) ...[
              Text('❄️ Congelé${batch.frozenAt == null ? '' : ' le ${formatDate(batch.frozenAt!)}'} : '
                  'la date de péremption ne compte pas.'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(c, 'thaw'),
                child: const Text('Décongeler (à consommer sous 24 h)'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('À consommer avant le'),
                subtitle: Text(formatDate(date)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: c, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setD(() => date = dateOnly(d));
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: opened,
                title: const Text('Entamé'),
                onChanged: (v) => setD(() => opened = v ?? false),
              ),
              const Text('Une fois ouvert, à finir sous :'),
              Wrap(spacing: 6, children: [
                for (final (label, n) in [('2 j', 2), ('3 j', 3), ('5 j', 5), ('1 sem.', 7), ('1 mois', 30)])
                  ActionChip(
                    label: Text(label),
                    // Entamé + date raccourcie, sans jamais la repousser.
                    onPressed: () => setD(() {
                      opened = true;
                      final d = today.add(Duration(days: n));
                      if (d.isBefore(date)) date = d;
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(c, 'freeze'),
                icon: const Icon(Icons.ac_unit),
                label: const Text('Congeler'),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Enregistrer')),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'freeze') {
    await state.freezeBatch(batch);
    if (context.mounted) showMessage(context, '${product.name} : congelé, la date ne compte plus');
    return;
  }
  if (action == 'thaw') {
    await state.thawBatch(batch);
    if (context.mounted) showMessage(context, '${product.name} : décongelé, à consommer avant demain');
    return;
  }
  final q = parseNumber(qty.text);
  if (q == null) return;
  if (q <= 0) {
    final snap = await state.deleteBatch(batch.id);
    if (context.mounted) showUndo(context, 'Lot supprimé', snap);
    return;
  }
  batch
    ..quantity = q
    ..expirationDate = dateOnly(date)
    ..location = location;
  if (opened && !batch.opened) batch.openedAt = today;
  batch.opened = opened;
  await state.saveBatch(batch);
}
