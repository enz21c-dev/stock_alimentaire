import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../models/models.dart';
import '../platform/platform.dart';
import 'common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<String?> _askName(BuildContext context, String title, [String initial = '']) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final state = AppScope.read(context);
    final d = DateTime.now();
    final name = 'stock_alimentaire_${dateToKey(d)}.json';
    final ok = await saveTextFile(name, state.exportJson());
    if (!ok && context.mounted) showMessage(context, 'Export annulé');
  }

  Future<void> _import(BuildContext context) async {
    final state = AppScope.read(context);
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !context.mounted) return;
    final text = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
    if (!context.mounted) return;
    if (!await confirm(
      context,
      'Remplacer toutes les données ?',
      'Le stock, les recettes, le planning et la liste de courses actuels seront remplacés par ceux du fichier « ${files.first.name} ».',
      ok: 'Remplacer',
    )) {
      return;
    }
    try {
      await state.importJson(text);
      if (context.mounted) showMessage(context, 'Sauvegarde importée ✔');
    } on FormatException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final used = {for (final p in state.products.values) p.category};

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: MaxWidth(
        width: 760,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          if (!isStandalone)
            Card(
              margin: const EdgeInsets.all(12),
              child: ListTile(
                leading: const Icon(Icons.add_to_home_screen),
                title: const Text("Installer l'appli sur l'écran d'accueil"),
                subtitle: const Text(
                    "Dans Safari : bouton Partager (carré avec une flèche) → « Sur l'écran d'accueil ». "
                    "L'appli s'ouvrira en plein écran et tes données seront mieux protégées."),
              ),
            ),
          _header(context, 'Alertes de péremption'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Prévenir avant la date'),
            subtitle: Text('${s.alertDays} jour${s.alertDays > 1 ? 's' : ''} avant (pastille orange et onglet « Bientôt périmés »)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: s.alertDays <= 0
                    ? null
                    : () {
                        s.alertDays--;
                        state.saveSettings();
                      },
              ),
              Text('${s.alertDays}', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: s.alertDays >= 30
                    ? null
                    : () {
                        s.alertDays++;
                        state.saveSettings();
                      },
              ),
            ]),
          ),
          _header(context, 'Catégories'),
          for (final c in s.categories)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(c),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Renommer',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final n = await _askName(context, 'Renommer la catégorie', c);
                    if (n == null || n.isEmpty || n == c) return;
                    if (s.categories.contains(n)) {
                      if (context.mounted) showMessage(context, 'Cette catégorie existe déjà');
                      return;
                    }
                    await state.renameCategory(c, n);
                  },
                ),
                IconButton(
                  tooltip: used.contains(c) ? 'Utilisée par des produits' : 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: used.contains(c) || s.categories.length <= 1
                      ? null
                      : () {
                          s.categories.remove(c);
                          state.saveSettings();
                        },
                ),
              ]),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Ajouter une catégorie'),
            onTap: () async {
              final n = await _askName(context, 'Nouvelle catégorie');
              if (n == null || n.isEmpty || s.categories.contains(n)) return;
              s.categories.add(n);
              await state.saveSettings();
            },
          ),
          _header(context, 'Emplacements'),
          SwitchListTile(
            secondary: const Icon(Icons.place_outlined),
            title: const Text('Ranger les produits par emplacement'),
            subtitle: const Text('Frigo, congélateur, placard… (facultatif)'),
            value: s.useLocations,
            onChanged: (v) {
              s.useLocations = v;
              state.saveSettings();
            },
          ),
          if (s.useLocations) ...[
            for (final l in s.locations)
              ListTile(
                leading: const Icon(Icons.place),
                title: Text(l),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Renommer',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final n = await _askName(context, "Renommer l'emplacement", l);
                      if (n == null || n.isEmpty || n == l || s.locations.contains(n)) return;
                      s.locations[s.locations.indexOf(l)] = n;
                      for (final b in state.batches.values.where((b) => b.location == l)) {
                        b.location = n;
                        await state.saveBatch(b);
                      }
                      await state.saveSettings();
                    },
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: state.batches.values.any((b) => b.location == l) || s.locations.length <= 1
                        ? null
                        : () {
                            s.locations.remove(l);
                            state.saveSettings();
                          },
                  ),
                ]),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Ajouter un emplacement'),
              onTap: () async {
                final n = await _askName(context, 'Nouvel emplacement');
                if (n == null || n.isEmpty || s.locations.contains(n)) return;
                s.locations.add(n);
                await state.saveSettings();
              },
            ),
          ],
          _header(context, 'Sauvegarde'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Tes données sont enregistrées uniquement sur cet appareil. Exporte une sauvegarde "
              "de temps en temps (dans Fichiers, iCloud Drive, par mail…) pour ne rien perdre et "
              "pour pouvoir changer d'appareil.",
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exporter une sauvegarde'),
            subtitle: Text(
                '${state.productsInStock.length} produits en stock · ${state.recipes.length} recettes'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importer une sauvegarde'),
            subtitle: const Text('Remplace toutes les données actuelles'),
            onTap: () => _import(context),
          ),
          _header(context, 'À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Stock Alimentaire'),
            subtitle: Text('Infos produits : Open Food Facts (openfoodfacts.org), base libre et collaborative.'),
          ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
