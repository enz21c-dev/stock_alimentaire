import 'package:sembast/sembast_memory.dart';

/// Hors navigateur (tests, Windows) : base en mémoire.
DatabaseFactory get platformDatabaseFactory => databaseFactoryMemory;
