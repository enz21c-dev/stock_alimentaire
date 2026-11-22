import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Android (et ordinateur) : base dans un fichier du dossier privé de l'appli.
Future<Database> openPlatformDatabase(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return databaseFactoryIo.openDatabase('${dir.path}/$name');
}
