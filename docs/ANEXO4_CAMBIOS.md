# Anexo 4 — revisión del equipo

Qué cambió al implementar el Anexo 4 revisado, dónde el código se aparta del
documento y qué falta decidir. Escrito el 8 sep 2026, contra la versión del
formulario que envió la investigadora principal.

---

## Lo que resuelve la revisión

Tres decisiones que llevaban meses abiertas se cierran solas con este
formulario:

- **Unidades del tiempo entre PVE y extubación.** Ahora es categórico, así que
  se acabó la ambigüedad de horas contra minutos que arrastraba
  `docs/PENDIENTE.md`.
- **Acumulación de funciones.** El documento nombra «reclutador-aplicador» como
  una función del estudio. No hace falta un valor nuevo: es la suma de las dos
  que ya existían, y es la combinación inofensiva. La peligrosa —aplicador más
  evaluador de desenlaces— sigue separada y sigue señalada.
- **Qué significa «eliminar» un paciente.** El documento lo define como salida
  del estudio con causa registrada, que es lo que el esquema ya permitía. Ver
  más abajo, porque tal como está descrito todavía tiene un problema.

Y el formulario adelgaza de once tipos de evento a seis, con la estratificación
calculándose dentro del enrolamiento en vez de ser un formulario aparte.

---

## Dos cosas que hay que corregir

### 1. El evaluador de desenlaces no puede ver el Módulo 1 entero

El documento dice que el evaluador «accede a la información del módulo 1». El
Módulo 1 contiene `Protocolo aplicado: ☐A ☐B`.

Eso descíega a quien mide el desenlace principal. Quien decide si una
reintubación a las 60 horas cuenta como fallo, sabiendo qué rama recibió el
paciente, ya no es un observador independiente — y no hace falta mala fe, basta
el sesgo inconsciente. Un revisor externo lo señalaría.

**Implementado**: el evaluador ve el Módulo 1 **menos la rama**. Es lo que el
sistema ya hacía y hay una prueba automática que falla si alguien lo rompe.
Necesita confirmación de la investigadora principal.

### 2. «Eliminar pacientes» tal como está descrito rompe el análisis

Los ejemplos del documento son reveladores: paciente traqueostomizado, paciente
al que se le hace una cuarta PVE, paciente que pide salir.

El tercero es legítimo. Los dos primeros no son criterios de salida: **son
desenlaces**. Un paciente que necesita traqueostomía o cuatro PVE es un paciente
al que le fue mal. Si se borra a los que van mal, y van mal más en una rama que
en otra —que es exactamente lo que pasaría si el protocolo funciona—, la
comparación queda inflada a favor de la rama buena. Eso es sesgo de attrition, y
anula la aleatorización.

Lo correcto es registrar la **salida del seguimiento** con fecha y causa,
dejando al paciente en el dataset. Quien decide después si el análisis es por
intención de tratar o por protocolo es el bioestadista, en la fase de análisis.
Un dato borrado no se recupera; uno marcado como retirado se puede excluir
cuando toque.

**No implementado todavía**: hace falta la decisión antes de escribirlo. La
base, mientras tanto, sigue impidiendo borrar a un paciente aleatorizado.

---

## Un cambio que conviene pensar dos veces

**Desaparecen RSBI, frecuencia respiratoria, Vt, volumen minuto, Pplateau y
driving pressure.**

Se entiende el motivo: son seis campos por PVE y por dos momentos, y hacen el
formulario pesado. Pero el RSBI es el predictor estándar de éxito de destete en
la literatura. Sin él, el dataset no se puede comparar con nada publicado, y es
lo primero que va a preguntar un revisor.

Hay una incoherencia interna que lo apunta: la lista de causas de fallo de la
PVE conserva «Debilidad muscular (por PIM o NIF)» y «Disfunción diafragmática
por ecografía». Se sigue esperando medición objetiva; solo que ya no se
registra.

**Recomendación**: conservar **un solo campo, el RSBI numérico al final de la
PVE**, opcional. Uno, no doce. Si después no se usa, no se usa; si hace falta y
no se recogió, no hay vuelta atrás.

**Implementado como pide el documento**: retirados los seis. Hay una prueba que
lo deja anotado para que su vuelta sea una decisión y no un descuido.

---

## Dónde el código se aparta del documento, y por qué

Todo esto está implementado así y pendiente de que lo confirme la investigadora
principal. Si algo no le parece, se cambia: son minutos.

### Tramos de categorías sin huecos ni solapes

El documento dejaba datos reales sin casilla donde ponerlos:

| Campo | En el documento | Implementado |
|---|---|---|
| Duración total de VMI | `≤5` · `6-14` · `>15` días | `5 días o menos` · `De 6 a 14 días` · `15 días o más` |
| Estancia en UCI | igual | igual |
| Tiempo de soporte post-extubación | `<24` · `24-48` · `48-72` h | `Menos de 24 h` · `De 24 a 47 h` · `De 48 a 71 h` · `72 h o más` |
| Duración de la PVE | `<30` · `30-60` · `60-120` · `>120` min | `Menos de 30` · `De 30 a 59` · `De 60 a 119` · `120 o más` |
| Tiempo entre PVE y extubación | `<1` · `1-4` · `4-12` · `>12` h | `Menos de 1` · `De 1 a 3` · `De 4 a 11` · `12 o más` |
| Categoría de IMC | `30-39,9` · `>40` | `Obeso` hasta 40 · `Superobeso` desde 40 |

Un paciente con exactamente 15 días de ventilación no tenía dónde registrarse; y
un soporte de 80 horas tampoco. En el sistema eso se traduce en un campo vacío o
en la casilla que le parezca a quien captura, y las dos cosas ensucian el
dataset.

### Causa de la intubación, mutuamente excluyente

El documento admite una sola marca pero ofrece «Respiratoria» y «EPOC
exacerbada», que no son alternativas — igual con «Cardiovascular» e
«Insuficiencia cardíaca».

Importa más de lo que parece: «causa de intubación EPOC exacerbada» es uno de
los cinco factores de la estratificación de riesgo. Dos médicos ante el mismo
paciente con EPOC descompensado marcarían distinto, y **al mismo paciente le
saldría un riesgo distinto según quién lo enrole**.

Implementado: las categorías generales llevan ahora «(otras causas)». Se
conservan todas las opciones del documento. De paso, «Poitrauma» → «Politrauma».

### El seguimiento post-egreso es un registro por contacto

El documento lo plantea como tres casillas (día 7, 14 y 28) dentro del Módulo 5.
Esas tres casillas se rellenan a lo largo de 28 días, así que el registro se
quedaría en borrador cuatro semanas — y los borradores no se sincronizan. El
dato viviría 28 días en un solo teléfono, que es el riesgo que más pesa hoy en
el proyecto.

Implementado: un registro por contacto, con el momento (`Día 7` · `Día 14` ·
`Día 28`), si falleció y la causa. La misma información, y cada contacto se
sincroniza en cuanto se registra. El dataset exportado puede volver a presentar
las tres columnas del documento.

### Lo que no se pregunta porque ya se sabe

- **«¿Se realizó PVE?»** dentro del formulario de PVE: si el registro existe, la
  prueba se hizo.
- **Fechas de PVE, de PVE exitosa y de extubación**: son la fecha del propio
  evento.
- **«Total de PVE intentadas»**: se cuenta de los registros. Pedir dos veces el
  mismo dato es pedir que discrepen.
- **«Edad ☐<65 ☐≥65»**: se deduce de la edad. El factor de riesgo por edad sí se
  marca aparte, porque forma parte del instrumento de estratificación.

### Fuera la función «observador»

El documento enumera las funciones que necesitan acceso y no la incluye. Una
función que nadie tiene asignada es superficie de permisos que nadie ha
revisado, y aquí los permisos sostienen el cegamiento. Si hace falta un monitor
externo, se vuelve a añadir — son diez líneas.

---

## Lo que el sistema no puede hacer, y conviene saberlo

**La detección de pacientes duplicados no puede ser completa sin conexión.**
Dentro de un mismo teléfono, sí. Entre dos teléfonos que llevan días sin
sincronizar es imposible: ninguno sabe lo que hizo el otro. Lo que sí se puede
es avisar en el momento con lo que el teléfono sepa, y detectarlo de verdad al
sincronizar.

**No queda registro de los pacientes excluidos.** Es coherente con el diseño —un
paciente que no entró no debe dejar rastro— pero significa que el diagrama de
flujo CONSORT (cribados → excluidos con motivo → aleatorizados) no se puede
construir desde el sistema. La práctica habitual es un registro de cribado
anónimo: solo el recuento y el motivo, sin identidad. Es barato de añadir y hay
que decidirlo con el CEI.

---

## Las dos preguntas del documento

**Alertas a los 7, 14 y 28 días del egreso**: sí, se puede, y funciona sin
conexión — la alarma la pone el propio teléfono. Al reclutador-aplicador y al
investigador principal, como pide.

**Aviso al evaluador cuando hay un paciente extubado**: sí. Con un matiz: si el
teléfono del evaluador no tiene conexión, el aviso le llega cuando la tenga. Eso
no hay forma de evitarlo.

**Las dos están implementadas.** Con una decisión de fondo que conviene
explicar: **no hay calendario guardado en ninguna parte**. Un aviso no es una
fila que se crea al enrolar y alguien tacha; se deduce cada vez, mirando qué
eventos existen y cuáles espera el protocolo a continuación.

La consecuencia práctica es que un aviso se apaga solo en cuanto se registra el
hito que lo cierra, sin que nadie tenga que acordarse de cancelarlo. Y que un
paciente que fallece deja de generar contactos de seguimiento sin ninguna
cancelación: los siguientes simplemente ya no proceden.

Cada persona ve solo los avisos que puede resolver. Una lista con cosas que uno
no puede atender se aprende a ignorar, y entonces deja de servir también para
las que sí.

**Y aquí hay una pregunta.** El documento pide que la alerta de seguimiento
llegue al reclutador-aplicador y al investigador principal, pero sitúa el
seguimiento post-egreso en el Módulo 5, que es del evaluador de desenlaces. Tal
como está implementado, el aviso lo ve quien puede registrar el contacto: el
evaluador y el investigador principal. Si quien debe llamar al paciente es el
reclutador-aplicador, entonces o él también registra ese contacto —y hay que
darle acceso a esa parte del Módulo 5— o llama él y registra otro. Conviene
decidirlo, porque son dos permisos distintos.

---

## Pendiente de decisión

1. **RSBI**: fuera del todo, o el número al final de la PVE.
2. **Acceso del evaluador al Módulo 1**: confirmar que se le oculta la rama.
3. **«Eliminar paciente» → «retirar del seguimiento»**: confirmar, y con qué
   causas.
4. Los tramos de categorías y la causa de intubación, tal como quedaron aquí.
5. **Registro de cribado anónimo** para el diagrama CONSORT: entra o no.
6. Los rangos de plausibilidad de peso, talla e IMC → `docs/RANGOS_PENDIENTES.md`.
