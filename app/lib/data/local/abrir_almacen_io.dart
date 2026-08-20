import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'almacen_local.dart';
import 'db/database_key.dart';
import 'db/sivap_database.dart';
import 'seed_data.dart';
import 'sqlite_study_repository.dart';

/// Abre el almacén local cifrado en móvil y escritorio.
Future<AlmacenLocal> abrirAlmacen(ModoAlmacen modo) async {
  final dir = await getApplicationDocumentsDirectory();
  final ruta = p.join(dir.path, modo.archivo);
  final clave = await DatabaseKey.obtenerOCrear();

  final base = SivapDatabase.abrir(ruta: ruta, claveHex: clave);
  final repo = SqliteStudyRepository(
    base,
    secuencia: Seed.secuenciaAleatorizacion,
  );

  if (modo == ModoAlmacen.demostracion) repo.sembrarDemostracionSiVacia();

  return AlmacenLocal(
    repo: repo,
    persistente: true,
    cifrado: true,
    descripcion: 'SQLite cifrado (SQLCipher) · ${modo.archivo}',
    advertencia: modo == ModoAlmacen.demostracion
        ? 'Base de demostración. Los pacientes que vea aquí no son reales.'
        : null,
  );
}
