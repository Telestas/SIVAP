import '../../domain/models/consent.dart';
import '../../domain/models/role.dart';
import '../../domain/models/visit_form_definition.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';

/// Datos de prueba del Hito 1 — los mismos casos que aparecen en el canvas de
/// diseño, para poder contrastar pantalla contra maqueta.
///
/// NADA de esto es un paciente real. El estudio no puede enrolar pacientes
/// reales hasta que el CEI apruebe protocolo y consentimiento
/// (`consentimientoAprobadoPorCei`).
class Seed {
  const Seed._();

  /// Fecha de referencia de los datos de demostración: el día que la maqueta
  /// retrata. Fijarla mantiene coherentes "vence hoy", "próx. día 10", etc.
  static final DateTime hoy = DateTime(2026, 8, 20);

  // ── Investigadores ─────────────────────────────────────────────
  static const morales = Investigador(
      id: 'u-morales',
      usuario: 'dra.morales',
      nombre: 'Dra. C. Morales',
      role: Role.recolector);
  static const perez = Investigador(
      id: 'u-perez', usuario: 'dr.perez', nombre: 'Dr. Pérez', role: Role.recolector);
  static const betancourt = Investigador(
      id: 'u-betancourt',
      usuario: 'dr.betancourt',
      nombre: 'Dr. Betancourt',
      role: Role.observador);
  static const guerra = Investigador(
      id: 'u-guerra',
      usuario: 'dr.guerra',
      nombre: 'Dr. A. Guerra',
      role: Role.administrador);

  static const investigadores = [morales, perez, betancourt, guerra];

  // ── Definición de formulario ───────────────────────────────────
  //
  // PENDIENTE (BASES §5): el listado real de variables por visita lo debe
  // entregar el equipo médico. Esto reproduce lo que muestra la maqueta.
  //
  // Para recoger un campo solo en ciertas visitas basta añadirle `dias: [1, 14]`
  // — la pantalla de captura ya lo respeta, no hay que tocar código.
  static const formulario = VisitFormDefinition(
    version: 'form-v0.1-borrador',
    diasVisita: [1, 3, 5, 10, 14],
    secciones: [
      FormSection(titulo: 'Signos vitales', campos: [
        FieldDefinition(
            key: 'ta',
            label: 'TA',
            unidad: 'mmHg',
            tipo: FieldType.texto,
            obligatorio: true),
        FieldDefinition(
            key: 'fc',
            label: 'FC',
            unidad: 'lpm',
            tipo: FieldType.numero,
            obligatorio: true,
            min: 40,
            max: 140),
        FieldDefinition(
            key: 'fr',
            label: 'FR',
            unidad: 'rpm',
            tipo: FieldType.numero,
            obligatorio: true,
            min: 10,
            max: 30),
        FieldDefinition(
            key: 'temp',
            label: 'Temp.',
            unidad: '°C',
            tipo: FieldType.numero,
            obligatorio: true,
            min: 35.0,
            max: 37.5,
            decimales: 1),
        FieldDefinition(
            key: 'spo2',
            label: 'SpO₂',
            unidad: '%',
            tipo: FieldType.numero,
            obligatorio: true,
            min: 92,
            max: 100),
        FieldDefinition(
            key: 'peso', label: 'Peso', unidad: 'kg', tipo: FieldType.numero, decimales: 1),
      ]),
      FormSection(titulo: 'Síntomas referidos', campos: [
        FieldDefinition(
            key: 'sintomas',
            label: 'Síntomas referidos',
            tipo: FieldType.seleccionMultiple,
            obligatorio: true,
            ancho: 2,
            opciones: ['Fiebre', 'Disnea', 'Tos', 'Cefalea', 'Náuseas', 'Astenia']),
      ]),
      FormSection(titulo: 'Observaciones', campos: [
        FieldDefinition(
            key: 'observaciones',
            label: 'Observaciones',
            tipo: FieldType.textoLargo,
            ancho: 2),
      ]),
    ],
  );

  // ── Consentimiento informado ───────────────────────────────────
  static const documentoConsentimiento = ConsentDocument(
    version: 'v2.1',
    codigoCei: 'CEI 2026-014',
    vigenteDesde: '14 mar 2026',
    parrafos: [
      'Se le invita a participar en un estudio de cohorte que compara el '
          'protocolo terapéutico vigente con un protocolo nuevo en pacientes '
          'ingresados en este servicio. La asignación a una de las dos ramas se '
          'realiza de forma aleatoria y no depende de su médico.',
      'Su participación es voluntaria. Puede retirarse en cualquier momento sin '
          'que ello afecte la atención médica que recibe.',
      'Sus datos clínicos se registran con un identificador interno. El análisis '
          'estadístico se realiza sobre datos sin su nombre ni su dirección.',
      'Si tiene dudas en cualquier momento del estudio, puede consultarlas con el '
          'investigador responsable del servicio.',
    ],
    declaraciones: [
      'He leído el documento y se me explicó verbalmente en un lenguaje comprensible.',
      'Acepto participar y que mis datos clínicos se usen con fines de investigación.',
    ],
  );

  static StudyConfig get config => const StudyConfig(
        nombreEstudio: 'Registro clínico de cohorte',
        centro: 'Hospital Provincial',
        servicio: 'Servicio de Medicina Interna',
        // Restricción CLAUDE.md §8: en falso hasta que el CEI apruebe.
        // Con el flag en falso la app funciona en modo demostración y bloquea
        // el enrolamiento de pacientes reales.
        consentimientoAprobadoPorCei: false,
        documentoConsentimiento: documentoConsentimiento,
        definicionFormulario: formulario,
      );

  // ── Secuencia de aleatorización ────────────────────────────────
  //
  // Generada por computadora a partir de una semilla fija (BASES §6). La
  // semilla del estudio real la fija el investigador principal UNA vez, antes
  // del primer paciente, y se deja por escrito en el acta: quien quiera
  // auditar la aleatorización regenera la secuencia con ella y compara.
  //
  // Esta semilla es de demostración. Cambiarla a mitad del estudio invalidaría
  // la trazabilidad de todo lo asignado hasta ese momento.
  static const semillaAleatorizacion = 20260814;
  static const longitudSecuencia = 120;

  static final secuenciaAleatorizacion = AllocationSequence.generada(
    semilla: semillaAleatorizacion,
    longitud: longitudSecuencia,
    ahora: DateTime(2026, 8, 14),
    etiqueta: 'secuencia 2026-A',
  );
}
