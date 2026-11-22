import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';
import 'common.dart';
import 'home_shell.dart';
import 'recipes_screen.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  DateTime _start = dateOnly(DateTime.now());

  Future<Recipe?> _pickRecipe(BuildContext context) async {
    final state = AppScope.read(context);
    final recipes = state.recipes.values.toList()
      ..sort((a, b) => normalizeName(a.name).compareTo(normalizeName(b.name)));
    if (recipes.isEmpty) {
      showMessage(context, "Crée d'abord une recette dans l'onglet Recettes.");
      return null;
    }
    return showDialog<Recipe>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Choisir une recette'),
        children: [
          for (final r in recipes)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, r), child: Text(r.name)),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, DateTime? date) async {
    final state = AppScope.read(context);
    final r = await _pickRecipe(context);
    if (r == null) return;
    await state.savePlanEntry(MealPlanEntry(recipeId: r.id, date: date));
    await state.refreshShoppingFromPlan();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final byDay = state.settings.planByDay;
    final entries = state.plan.values.where((e) => state.recipes.containsKey(e.recipeId)).toList();
    final today = dateOnly(DateTime.now());

    final children = <Widget>[_NeedsCard()];

    if (byDay) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(
            tooltip: 'Semaine précédente',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _start = _start.subtract(const Duration(days: 7))),
          ),
          Expanded(
            child: Text(
              'Du ${formatDate(_start)} au ${formatDate(_start.add(const Duration(days: 6)))}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Semaine suivante',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _start = _start.add(const Duration(days: 7))),
          ),
        ]),
      ));
      final late = entries.where((e) => e.date != null && e.date!.isBefore(today) && !e.done).toList();
      if (late.isNotEmpty && !_start.isAfter(today)) {
        children.add(_DaySection(title: 'Jours passés, pas encore faites', entries: late));
      }
      for (var i = 0; i < 7; i++) {
        final day = _start.add(Duration(days: i));
        children.add(_DaySection(
          title: day == today ? "Aujourd'hui" : formatDay(day),
          entries: entries.where((e) => e.date == day).toList(),
          onAdd: () => _add(context, day),
        ));
      }
      final undated = entries.where((e) => e.date == null).toList();
      if (undated.isNotEmpty) {
        children.add(_DaySection(title: 'Sans date', entries: undated));
      }
    } else {
      children.add(_DaySection(
        title: 'Recettes prévues',
        entries: entries..sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0)),
        onAdd: () => _add(context, null),
        showDate: true,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear') await state.clearDonePlan();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Retirer les recettes faites')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.view_week), label: Text('Par jour')),
                ButtonSegment(value: false, icon: Icon(Icons.list), label: Text('Liste libre')),
              ],
              selected: {byDay},
              onSelectionChanged: (s) {
                state.settings.planByDay = s.first;
                state.saveSettings();
              },
            ),
          ),
        ),
      ),
      floatingActionButton: byDay
          ? null
          : FloatingActionButton.extended(
              heroTag: 'plan',
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une recette'),
              onPressed: () => _add(context, null),
            ),
      body: MaxWidth(child: ListView(padding: const EdgeInsets.only(bottom: 96), children: children)),
    );
  }
}

/// Résumé : ce qui manque dans le stock pour les recettes prévues.
class _NeedsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pending = state.plan.values.where((e) => !e.done && state.recipes.containsKey(e.recipeId));
    if (pending.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Aucune recette prévue'),
          subtitle: Text('Ajoute des recettes pour voir ce qu\'il manque dans ton stock.'),
        ),
      );
    }
    final missing = state.needs.where((n) => n.isMissing).toList();
    final scheme = Theme.of(context).colorScheme;
    if (missing.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: ListTile(
          leading: Icon(Icons.check_circle, color: statusColor(ExpiryStatus.ok)),
          title: const Text('Tout est en stock pour les recettes prévues'),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.all(12),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.shopping_basket, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Il faut acheter ${missing.length} ingrédient${missing.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          for (final n in missing)
            Text(
              '• ${n.name} : il manque ${_fmt(n.missing, n.unit)}'
              '${n.available > 0 ? ' (en stock : ${_fmt(n.available, n.unit)})' : ''}',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.shopping_cart),
            label: const Text('Voir la liste de courses'),
            onPressed: () async {
              await state.refreshShoppingFromPlan();
              if (context.mounted) HomeShell.goTo(context, HomeShell.shopping);
            },
          ),
        ]),
      ),
    );
  }

  static String _fmt(double q, String base) {
    final (v, u) = humanize(q, base);
    return formatQty(v, u);
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.title, required this.entries, this.onAdd, this.showDate = false});
  final String title;
  final List<MealPlanEntry> entries;
  final VoidCallback? onAdd;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            if (onAdd != null && showDate == false)
              IconButton(tooltip: 'Ajouter une recette', icon: const Icon(Icons.add), onPressed: onAdd),
          ]),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('—', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ),
          for (final e in entries)
            Builder(builder: (context) {
              final r = state.recipes[e.recipeId]!;
              return ListTile(
                dense: true,
                leading: ProductAvatar(photoData: r.photoData, name: r.name, size: 36),
                title: Text(
                  r.name,
                  style: e.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                subtitle: showDate && e.date != null ? Text(formatDay(e.date!)) : (e.done ? const Text('Faite') : null),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id)),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!e.done)
                    TextButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Faite'),
                      onPressed: () => cookRecipe(context, r, entry: e),
                    ),
                  IconButton(
                    tooltip: 'Retirer du planning',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await state.deletePlanEntry(e.id);
                      await state.refreshShoppingFromPlan();
                    },
                  ),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
