import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/units.dart';
import '../models/models.dart';
import 'common.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final _name = TextEditingController();
  final _qty = TextEditingController();
  final _focus = FocusNode();
  String _unit = 'pièce';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).refreshShoppingFromPlan();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _addManual() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final q = parseNumber(_qty.text);
    await AppScope.read(context).saveShoppingItem(
      ShoppingItem(name: n, quantity: q, unit: q == null ? null : _unit),
    );
    _name.clear();
    _qty.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.shopping.values.toList()
      ..sort((a, b) {
        if (a.checked != b.checked) return a.checked ? 1 : -1;
        return normalizeName(a.name).compareTo(normalizeName(b.name));
      });
    final checked = items.where((i) => i.checked).map((i) => i.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste de courses'),
        actions: [
          IconButton(
            tooltip: 'Mettre à jour depuis le planning',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await state.refreshShoppingFromPlan();
              if (context.mounted) showMessage(context, 'Liste mise à jour depuis le planning');
            },
          ),
          if (checked.isNotEmpty)
            IconButton(
              tooltip: 'Retirer les articles cochés',
              icon: const Icon(Icons.remove_done),
              onPressed: () => state.deleteShoppingItems(checked),
            ),
        ],
      ),
      body: MaxWidth(
        width: 760,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _name,
                  focusNode: _focus,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Ajouter un article…', isDense: true),
                  onSubmitted: (_) => _addManual(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Qté', isDense: true),
                  onSubmitted: (_) => _addManual(),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _unit,
                items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: (v) => setState(() => _unit = v!),
              ),
              IconButton.filled(onPressed: _addManual, icon: const Icon(Icons.add)),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    text: 'Rien à acheter.\nLes ingrédients manquants du planning apparaîtront ici automatiquement.',
                  )
                : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                    for (final i in items)
                      Dismissible(
                        key: ValueKey(i.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete),
                        ),
                        onDismissed: (_) => state.deleteShoppingItems([i.id]),
                        child: CheckboxListTile(
                          value: i.checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) {
                            i.checked = v ?? false;
                            state.saveShoppingItem(i);
                          },
                          title: Text(
                            i.name,
                            style: i.checked
                                ? TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Theme.of(context).colorScheme.outline,
                                  )
                                : null,
                          ),
                          subtitle: i.quantity == null && !i.auto
                              ? null
                              : Text([
                                  if (i.quantity != null) formatQty(i.quantity!, i.unit ?? 'pièce'),
                                  if (i.auto) 'pour le planning',
                                ].join(' · ')),
                          secondary: i.auto ? const Icon(Icons.calendar_month, size: 20) : null,
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
