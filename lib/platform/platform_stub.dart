// Version hors navigateur (tests) : ne fait rien.

Future<void> playBeep() async {}

void unlockAudio() {}

/// Renvoie true si le fichier a été proposé à l'utilisateur.
Future<bool> saveTextFile(String fileName, String content) async => false;

Future<void> requestPersistentStorage() async {}

/// true si l'appli est lancée depuis l'écran d'accueil (mode « appli »).
bool get isStandalone => false;
