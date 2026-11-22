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
  _Sort _sort = _Sort.expiry;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = normalizeName(_search.text);

    final all = state.productsInStock;
    final categories = {for (final p in all) p.category}.toList()
      ..sort((a, b) => state.settings.categories.indexOf(a).compareTo(state.settings.categories.indexOf(b)));

    final products = all.where((p) {
      if (_category != null && p.category != _category) return false;
      if (q.isEmpty) return true;
      return normalizeName('${p.name} ${p.brand ?? ''}').contains(q);
    }).toList();
    final nearest = {for (final p in products) p.id: state.batchesOf(p.id).first.expirationDate};
    products.sort((a, b) => _sort == _Sort.name
        ? normalizeName(a.name).compareTo(normalizeName(b.name))
        : nearest[a.id]!.compareTo(nearest[b.id]!));

    final expiring = state.expiringBatches.length;
    final anyExpired = state.expiringBatches.any((b) => daysUntil(b.expirationDate) < 0);
    final bannerBg = anyExpired ? Theme.of(context).colorScheme.errorContainer : const Color(0xFFFFE0B2);
    final bannerFg = anyExpired ? Theme.of(context).colorScheme.onErrorContainer : const Color(0xFF5D3A00);

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
            unlockAudio(); // Safari n'autorise le son qu'après un appui
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
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _search.clear()),
                      ),
              ),
            ),
          ),
          if (categories.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in [null, ...categories])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c ?? 'Tout'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
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
    final alert = state.settings.alertDays;
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
            Text('${formatQty(total, product.unit)} au total${lots.length > 1 ? ' · ${lots.length} lots' : ''}'),
            ExpiryChip(first.expirationDate, alertDays: alert),
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddArticleScreen(product: product)),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier le produit'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditProductScreen(product: product)),
              ),
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

  Future<void> _edit(BuildContext context) async {
    final state = AppScope.read(context);
    final qty = TextEditingController(text: formatNumber(batch.quantity));
    var date = batch.expirationDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Modifier le lot'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantité', suffixText: product.unit),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Date de péremption'),
              subtitle: Text(formatDate(date)),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setD(() => date = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final q = parseNumber(qty.text);
    if (ok != true || q == null) return;
    if (q <= 0) {
      final snap = await state.deleteBatch(batch.id);
      if (context.mounted) showUndo(context, 'Lot supprimé', snap);
      return;
    }
    batch
      ..quantity = q
      ..expirationDate = dateOnly(date);
    await state.saveBatch(batch);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = daysUntil(batch.expirationDate);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: StatusDot(expiryStatus(days, alertDays: state.settings.alertDays)),
      title: Text(formatQty(batch.quantity, product.unit)),
      subtitle: Text('À consommer avant le ${formatDate(batch.expirationDate)} · ${expiryLabel(days)}'),
      onTap: () => _edit(context),
      trailing: IconButton(
        tooltip: 'Supprimer ce lot',
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final snap = await state.deleteBatch(batch.id);
          if (context.mounted) showUndo(context, 'Lot de ${product.name} supprimé', snap);
        },
      ),
    );
  }
}
