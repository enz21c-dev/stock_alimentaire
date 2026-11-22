import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import 'common.dart';

/// Lots périmés ou qui périment dans le délai d'alerte (Réglages).
class ExpiringScreen extends StatelessWidget {
  const ExpiringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lots = state.expiringBatches;
    final expired = lots.where((b) => daysUntil(b.expirationDate) < 0).toList();
    final soon = lots.where((b) => daysUntil(b.expirationDate) >= 0).toList();
    final alert = state.settings.alertDays;

    Widget header(String text, Color color) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Bientôt périmés')),
      body: lots.isEmpty
          ? EmptyState(
              icon: Icons.check_circle_outline,
              text: 'Rien ne périme dans les $alert prochains jours. 👍',
            )
          : MaxWidth(
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                if (expired.isNotEmpty) ...[
                  header('Périmés', statusColor(ExpiryStatus.expired)),
                  for (final b in expired) _ExpiringTile(batch: b),
                ],
                if (soon.isNotEmpty) ...[
                  header('À consommer dans les $alert jours', statusColor(ExpiryStatus.soon)),
                  for (final b in soon) _ExpiringTile(batch: b),
                ],
              ]),
            ),
    );
  }
}

class _ExpiringTile extends StatelessWidget {
  const _ExpiringTile({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.products[batch.productId];
    if (p == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          ProductAvatar.of(p),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${formatQty(batch.quantity, p.unit)} · ${formatDate(batch.expirationDate)}'),
              const SizedBox(height: 4),
              ExpiryChip(batch.expirationDate, alertDays: state.settings.alertDays),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              icon: const Icon(Icons.restaurant),
              label: const Text('Utilisé'),
              onPressed: () async {
                final q = p.unit == 'pièce' && batch.quantity <= 1
                    ? batch.quantity
                    : await askQuantity(context,
                        title: 'Quantité de « ${p.name} » utilisée',
                        unit: p.unit,
                        initial: batch.quantity,
                        max: batch.quantity);
                if (q == null || !context.mounted) return;
                final snap = q >= batch.quantity
                    ? await state.deleteBatch(batch.id)
                    : await _reduce(state, q);
                if (context.mounted) showUndo(context, '${p.name} : ${formatQty(q, p.unit)} utilisé(s)', snap);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Jeté'),
              onPressed: () async {
                final snap = await state.deleteBatch(batch.id);
                if (context.mounted) showUndo(context, '${p.name} retiré du stock', snap);
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Future<UndoSnapshot> _reduce(AppState state, double q) async {
    final snap = UndoSnapshot([batch.copy()]);
    batch.quantity -= q;
    await state.saveBatch(batch);
    return snap;
  }
}
