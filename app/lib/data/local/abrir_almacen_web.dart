import 'almacen_local.dart';
import 'in_memory_study_repository.dart';

/// Abre el almacén en el navegador.
///
/// No hay almacén local cifrado en web, y no es una carencia que haya que
/// tapar: SQLCipher cifra un archivo, y en el navegador no hay archivo. Cifrar
/// a mano lo que se guarda en IndexedDB dejaría la clave en el propio
/// navegador, lo que no protege de nadie.
///
/// La salida correcta es que la web —el panel de administración— no guarde
/// nada localmente y lea del servidor. Mientras el backend no exista, arranca
/// en memoria y lo dice en pantalla.
Future<AlmacenLocal> abrirAlmacen(ModoAlmacen modo) async => AlmacenLocal(
      repo: InMemoryStudyRepository(),
      persistente: false,
      cifrado: false,
      descripcion: 'En memoria (navegador)',
      advertencia: 'En el navegador los datos no se guardan ni se cifran: al '
          'cerrar la pestaña se pierden. No usar para captura de datos reales.',
    );
