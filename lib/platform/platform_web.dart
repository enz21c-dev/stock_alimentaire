// Fonctions propres au navigateur (Safari sur iPad, Chrome/Edge sur PC).

import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.AudioContext? _audio;

/// À appeler lors d'un appui de l'utilisateur : Safari n'autorise le son
/// qu'après une interaction.
void unlockAudio() {
  try {
    _audio ??= web.AudioContext();
    if (_audio!.state == 'suspended') _audio!.resume();
  } catch (_) {}
}

/// Petit « bip » de lecture réussie (l'iPad ne sait pas vibrer).
Future<void> playBeep() async {
  try {
    unlockAudio();
    final ctx = _audio!;
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = 1200;
    gain.gain.value = 0.15;
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.12);
  } catch (_) {}
}

/// Propose le fichier : feuille de partage sur iPad (Enregistrer dans
/// Fichiers, AirDrop, mail…), sinon téléchargement classique.
Future<bool> saveTextFile(String fileName, String content) async {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  try {
    final file = web.File([content.toJS].toJS, fileName,
        web.FilePropertyBag(type: 'application/json'));
    final data = web.ShareData(files: [file].toJS);
    if (web.window.navigator.canShare(data)) {
      await web.window.navigator.share(data).toDart;
      return true;
    }
  } catch (e) {
    // Partage annulé par l'utilisateur : on ne retente pas.
    if (e.toString().contains('AbortError')) return false;
  }
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.append(a);
  a.click();
  a.remove();
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return true;
}

/// Demande au navigateur de ne pas effacer les données de l'appli.
Future<void> requestPersistentStorage() async {
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {}
}

bool get isStandalone {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}
