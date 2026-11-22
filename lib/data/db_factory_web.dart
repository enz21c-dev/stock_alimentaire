import 'package:sembast_web/sembast_web.dart';

/// Dans le navigateur : base stockée dans IndexedDB, sur l'appareil.
DatabaseFactory get platformDatabaseFactory => databaseFactoryWeb;
