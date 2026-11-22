import 'package:sembast/sembast_memory.dart';

/// Repli (plateforme inconnue) : base en mémoire.
Future<Database> openPlatformDatabase(String name) => databaseFactoryMemory.openDatabase(name);
