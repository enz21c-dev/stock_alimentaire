// Version hors navigateur (Android, tests).

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Vibration courte quand un code-barres est lu.
Future<void> playBeep() async {
  try {
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

void unlockAudio() {}

/// Ouvre la fenêtre « Enregistrer sous » d'Android. true si le fichier est enregistré.
Future<bool> saveTextFile(String fileName, String content) async {
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
      dialogTitle: 'Enregistrer la sauvegarde',
    );
    return uri != null;
  } catch (_) {
    return false;
  }
}

Future<void> requestPersistentStorage() async {}

/// true si l'appli est lancée depuis l'écran d'accueil (mode « appli »).
bool get isStandalone => true;
