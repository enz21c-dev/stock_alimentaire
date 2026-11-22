import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/app_state.dart';
import '../models/models.dart';
import '../platform/platform.dart';
import '../services/open_food_facts.dart';
import 'add_article_screen.dart';

/// Scan en rafale : la caméra reste ouverte, chaque code lu ouvre une petite
/// fiche d'ajout, puis on revient au scan.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
    facing: CameraFacing.back,
  );

  bool _busy = false;
  String? _lastCode;
  DateTime _lastTime = DateTime(2000);
  int _added = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || _busy) return;
    final now = DateTime.now();
    // Évite de relire le même article en boucle.
    if (code == _lastCode && now.difference(_lastTime) < const Duration(seconds: 3)) return;
    _lastCode = code;
    _lastTime = now;
    playBeep();
    _handleCode(code);
  }

  Future<void> _handleCode(String code) async {
    setState(() => _busy = true);
    final state = AppScope.read(context);
    final known = state.productByBarcode(code);

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => _ScanSheet(code: code, known: known),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (added == true) _added++;
      _lastTime = DateTime.now(); // laisse le temps de retirer l'article de la caméra
    });
  }

  Future<void> _typeCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Saisir le code-barres'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'ex. 3017620422003'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Chercher')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) _handleCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_added == 0 ? 'Scanner' : 'Scanner · $_added ajouté${_added > 1 ? 's' : ''}'),
        actions: [
          IconButton(tooltip: 'Saisir le code', icon: const Icon(Icons.keyboard), onPressed: _typeCode),
          IconButton(
            tooltip: 'Lampe',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Changer de caméra',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.no_photography, color: Colors.white, size: 56),
                const SizedBox(height: 12),
                Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? "L'accès à la caméra a été refusé.\nAutorise-le dans les réglages de Safari (aA → Réglages du site web → Caméra)."
                      : 'Caméra indisponible (${error.errorCode.name}).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _typeCode,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Saisir le code à la main'),
                ),
              ]),
            ),
          ),
        ),
        // Cadre de visée
        IgnorePointer(
          child: Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: _busy ? Colors.greenAccent : Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Text(
            'Vise le code-barres. La caméra reste ouverte pour enchaîner les articles.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), shadows: const [Shadow(blurRadius: 4)]),
          ),
        ),
      ]),
    );
  }
}

/// Fiche affichée après un scan : cherche le produit puis montre le formulaire.
class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.code, this.known});
  final String code;
  final Product? known;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  late final Future<(OffProduct?, String?)> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = widget.known != null ? Future.value((null, null)) : _fetch();
  }

  Future<(OffProduct?, String?)> _fetch() async {
    try {
      final p = await OpenFoodFacts.lookup(widget.code);
      return (p, p == null ? 'Produit inconnu d\'Open Food Facts : complète la fiche.' : null);
    } catch (_) {
      return (null, 'Pas de connexion à Open Food Facts : complète la fiche à la main.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: FutureBuilder(
        future: _lookup,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Recherche du produit…'),
                ]),
              ),
            );
          }
          final (off, message) = snap.data!;
          return SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ArticleForm(
                product: widget.known,
                off: off,
                barcode: widget.code,
                saveLabel: 'Ajouter et continuer',
                onSaved: () => Navigator.pop(context, true),
              ),
            ]),
          );
        },
      ),
    );
  }
}
