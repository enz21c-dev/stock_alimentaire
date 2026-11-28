import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/stock_logic.dart';

class DateReadResult {
  final List<FoundDate> dates;
  final String? error;
  DateReadResult(this.dates, [this.error]);
}

/// Lit la date de péremption sur une photo de l'emballage, sur le téléphone
/// (Google ML Kit, sans internet). Règle : on ne propose que des dates
/// réellement lues et complètes ; l'utilisateur confirme toujours.
class DateReader {
  DateReader._();

  /// Disponible sur Android uniquement (pas dans le navigateur).
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Prend une photo et renvoie les dates trouvées ; null si la photo est annulée.
  static Future<DateReadResult?> readFromCamera() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 92);
    } catch (_) {
      return DateReadResult(const [], "Impossible d'ouvrir l'appareil photo.");
    }
    if (file == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return DateReadResult(findDates(text.text));
    } catch (_) {
      return DateReadResult(const [], "La lecture n'a pas marché. Saisis la date à la main.");
    } finally {
      await recognizer.close();
    }
  }
}
