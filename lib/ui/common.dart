import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../logic/stock_logic.dart';
import '../logic/units.dart';
import '../models/models.dart';

final _dateFmt = DateFormat('d MMM y', 'fr_FR');
final _dayFmt = DateFormat('EEEE d MMMM', 'fr_FR');

String formatDate(DateTime d) => _dateFmt.format(d);
String formatDay(DateTime d) {
  final s = _dayFmt.format(d);
  return s[0].toUpperCase() + s.substring(1);
}

Color statusColor(ExpiryStatus s) => switch (s) {
      ExpiryStatus.ok => const Color(0xFF2E7D32),
      ExpiryStatus.soon => const Color(0xFFEF6C00),
      ExpiryStatus.expired => const Color(0xFFC62828),
    };

/// Pastille de couleur selon la date de péremption.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 12});
  final ExpiryStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: statusColor(status), shape: BoxShape.circle),
      );
}

/// Petite étiquette « dans 3 jours » colorée.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip(this.date, {super.key, required this.alertDays});
  final DateTime date;
  final int alertDays;

  @override
  Widget build(BuildContext context) {
    final d = daysUntil(date);
    final c = statusColor(expiryStatus(d, alertDays: alertDays));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(expiryLabel(d), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Widget _tag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );

/// Étiquette « entamé ».
class OpenedTag extends StatelessWidget {
  const OpenedTag({super.key});
  @override
  Widget build(BuildContext context) => _tag('entamé', const Color(0xFF6A1B9A));
}

/// Étiquette d'un lot : « congelé » (pas de date), sinon la date + « entamé ».
class LotTag extends StatelessWidget {
  const LotTag(this.batch, {super.key, required this.alertDays});
  final Batch batch;
  final int alertDays;

  @override
  Widget build(BuildContext context) {
    if (batch.frozen) {
      return _tag('❄️ congelé${batch.frozenAt == null ? '' : ' le ${formatDate(batch.frozenAt!)}'}',
          const Color(0xFF1565C0));
    }
    return Wrap(spacing: 6, children: [
      ExpiryChip(batch.expirationDate, alertDays: alertDays),
      if (batch.opened) const OpenedTag(),
    ]);
  }
}

/// « 1 378 kcal »
String kcalText(double k) => '${NumberFormat.decimalPattern('fr_FR').format(k.round())} kcal';

/// Message en bas avec un bouton d'action (ex. « Ajouter au stock »).
void showAction(BuildContext context, String message, String label, VoidCallback onPressed) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 7),
    persist: false,
    action: SnackBarAction(label: label, onPressed: onPressed),
  ));
}

final Map<String, Uint8List> _photoCache = {};

Uint8List decodePhoto(String data) {
  if (_photoCache.length > 200) _photoCache.clear();
  return _photoCache.putIfAbsent(data, () => base64Decode(data));
}

/// Photo d'un produit (prise avec l'iPad, ou Open Food Facts), sinon initiale.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, this.photoData, this.photoUrl, required this.name, this.size = 48});
  final String? photoData;
  final String? photoUrl;
  final String name;
  final double size;

  factory ProductAvatar.of(Product p, {double size = 48}) =>
      ProductAvatar(photoData: p.photoData, photoUrl: p.photoUrl, name: p.name, size: size);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.45, color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
      ),
    );
    Widget child = fallback;
    if (photoData != null) {
      child = Image.memory(decodePhoto(photoData!), fit: BoxFit.cover, gaplessPlayback: true);
    } else if (photoUrl != null) {
      child = Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 5),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// Prend une photo (ou en choisit une) et la renvoie en base64, réduite.
Future<String?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: const Text('Prendre une photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: const Text('Choisir dans les photos'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  final file = await ImagePicker().pickImage(source: source, maxWidth: 500, maxHeight: 500, imageQuality: 70);
  if (file == null) return null;
  return base64Encode(await file.readAsBytes());
}

/// Affiche un message avec un bouton « Annuler » pendant quelques secondes.
void showUndo(BuildContext context, String message, UndoSnapshot snap) {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 6),
    persist: false,
    action: SnackBarAction(label: 'Annuler', onPressed: () => state.undo(snap)),
  ));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Oui'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Demande une quantité (ex. combien de yaourts utilisés).
Future<double?> askQuantity(BuildContext context,
    {required String title, required String unit, double initial = 1, double? max}) {
  final ctrl = TextEditingController(text: formatNumber(initial));
  return showDialog<double>(
    context: context,
    builder: (c) {
      void submit() {
        final v = parseNumber(ctrl.text);
        if (v != null && v > 0) Navigator.pop(c, v);
      }

      return AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: unit, labelText: 'Quantité'),
            onSubmitted: (_) => submit(),
          ),
          if (max != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('En stock : ${formatQty(max, unit)}', style: Theme.of(c).textTheme.bodySmall),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: submit, child: const Text('Valider')),
        ],
      );
    },
  );
}

/// Message centré quand une liste est vide.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Limite la largeur du contenu sur grand écran (iPad à l'horizontale).
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 900});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}
