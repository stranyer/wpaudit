// Archivo de Zona Cero: documentos que el Enlace encuentra y desbloquea jugando.
// Todo el lore es original. Los nombres de organismos y empresas son ficticios.

enum LoreCategory { informe, diario, transmision, corpus }

extension LoreCategoryLabel on LoreCategory {
  String get label => switch (this) {
        LoreCategory.informe => 'Informes',
        LoreCategory.diario => 'Diarios',
        LoreCategory.transmision => 'Transmisiones',
        LoreCategory.corpus => 'Corpus',
      };
}

/// Condición de desbloqueo sobre el progreso del jugador.
enum UnlockStat { always, level, kills, explored, looted, donated, bruteKills, shelters }

class LoreUnlock {
  const LoreUnlock(this.stat, [this.value = 0]);
  final UnlockStat stat;
  final int value;

  String get hint => switch (stat) {
        UnlockStat.always => 'Disponible',
        UnlockStat.level => 'Alcanzá el grado $value',
        UnlockStat.kills => 'Neutralizá $value infectados',
        UnlockStat.explored => 'Explorá $value sectores',
        UnlockStat.looted => 'Recuperá $value suministros',
        UnlockStat.donated => 'Aportá $value recursos a un nodo',
        UnlockStat.bruteKills => 'Neutralizá un Bruto',
        UnlockStat.shelters => 'Suturá tu primer nodo',
      };
}

class LoreFile {
  const LoreFile({
    required this.id,
    required this.category,
    required this.code,
    required this.title,
    required this.date,
    required this.author,
    required this.body,
    this.unlock = const LoreUnlock(UnlockStat.always),
    this.stamp,
  });

  final String id;
  final LoreCategory category;
  final String code;
  final String title;
  final String date;
  final String author;
  final String body;
  final LoreUnlock unlock;
  final String? stamp;
}

const loreFiles = <LoreFile>[
  LoreFile(
    id: 'desam-001',
    category: LoreCategory.informe,
    code: 'DESAM/INF-001',
    title: 'Activación del Protocolo Sutura',
    date: 'Día 2 · 04:12',
    author: 'Dirección de Emergencias Sanitarias Metropolitanas',
    stamp: 'URGENTE',
    body: '''Se declara la emergencia sanitaria en el Área Metropolitana. La cepa AMB-0, denominada informalmente "la Ámbar", supera la capacidad de contención hospitalaria en las primeras 31 horas.

Ante la caída progresiva de la red celular, se activa el PROTOCOLO SUTURA:

1. Se distribuyen terminales médicas de campo VITA-7 a voluntarios registrados, en adelante ENLACES.
2. Cada Enlace instala antenas de relevo en terrazas, torres y refugios para reconstruir una red mínima entre puntos seguros.
3. Toda ubicación personal se transmite difuminada. Nadie debe poder ser rastreado hasta su casa.

Los Enlaces no son personal sanitario. No intenten tratar a un infectado. Escaneen, abastezcan, suturen. Repito: escaneen, abastezcan, suturen.''',
  ),
  LoreFile(
    id: 'corpus-ambar',
    category: LoreCategory.corpus,
    code: 'CORPUS/A',
    title: 'Ámbar (cepa AMB-0)',
    date: 'Actualizado continuamente',
    author: 'Base de conocimiento VITA-7',
    body: '''Agente patógeno de origen no determinado. El contagio se produce por mordedura y por esporas en espacios cerrados. Los infectados presentan pupilas de color ámbar, insensibilidad al dolor y atracción por el sonido.

La concentración de esporas se representa en el mapa con CURVAS DE CONTAGIO: cuanto más juntas están las líneas rojas, más denso es el foco. Las zonas con focos rotan cada pocas horas.''',
  ),
  LoreFile(
    id: 'corpus-enlace',
    category: LoreCategory.corpus,
    code: 'CORPUS/E',
    title: 'Enlace',
    date: 'Actualizado continuamente',
    author: 'Base de conocimiento VITA-7',
    body: '''Voluntario del Protocolo Sutura con una terminal VITA-7 asignada. Un Enlace recorre la ciudad a pie, escanea el entorno con el pulso de la terminal, recupera suministros y los lleva a los nodos de la red.

Regla de oro de los Enlaces: mirá la calle, no la pantalla. La terminal bloquea las interacciones si detecta que te movés en un vehículo.''',
  ),
  LoreFile(
    id: 'corpus-pulsos',
    category: LoreCategory.corpus,
    code: 'CORPUS/P',
    title: 'Pulsos',
    date: 'Actualizado continuamente',
    author: 'Base de conocimiento VITA-7',
    body: '''Un pulso es una señal corta que un Enlace le manda a otro cuando usa algo que dejó en la red: una baliza, una caja de suministros, una barricada. No da recursos. Avisa que alguien pasó por ahí y que eso le sirvió.

Muchos Enlaces dicen que los pulsos son lo único que los hace seguir caminando.''',
  ),
  LoreFile(
    id: 'diario-lucia-3',
    category: LoreCategory.diario,
    code: 'DIARIO/LZ-03',
    title: 'Lucía, día 3',
    date: 'Día 3',
    author: 'Lucía Z., Enlace de Balvanera',
    unlock: LoreUnlock(UnlockStat.level, 2),
    body: '''Hoy instalé mi primera antena arriba del kiosco de Lavalle. La terminal dice "NODO SUTURADO" con una voz que parece de ascensor. Me reí sola en la terraza.

Desde arriba se ven los Caminantes dando vueltas alrededor del Obelisco, como si esperaran el colectivo. No sé qué esperan. Nosotros tampoco.''',
  ),
  LoreFile(
    id: 'tx-104-madrugada',
    category: LoreCategory.transmision,
    code: 'TX/104.3',
    title: 'Radio 104.3, madrugada',
    date: 'Día 5 · 03:40',
    author: 'Transmisión pirata',
    unlock: LoreUnlock(UnlockStat.explored, 5),
    body: '''—...si me escuchan, no bajen al subte. Repito, no bajen al subte. La línea C está tomada desde Constitución hasta Diagonal Norte.

—Los chillones atraen a los demás. Si escuchás uno, no te quedes a mirar. Rajá.

—Hay un nodo andando en Plaza Lavalle. Llevá agua. La gente de ahí comparte lo que tiene.

—Esto es 104.3. Seguimos al aire mientras haya batería.''',
  ),
  LoreFile(
    id: 'desam-014',
    category: LoreCategory.informe,
    code: 'DESAM/INF-014',
    title: 'Clasificación de infectados',
    date: 'Día 6',
    author: 'DESAM · Unidad de Respuesta',
    unlock: LoreUnlock(UnlockStat.kills, 3),
    body: '''CAMINANTE: lento, previsible. Dos o tres golpes firmes alcanzan.

CORREDOR: infección reciente. Ataca en ráfagas de dos golpes. Escapar es difícil: conviene pelear.

HINCHADO: libera esporas al morir. Neutralizar a distancia siempre que sea posible.

CHILLÓN: su grito atrae refuerzos y lo protege. Prioridad absoluta: terminarlo rápido.

BRUTO: masa muscular extrema. Antes de embestir se agacha. CUBRIRSE EN ESE MOMENTO lo deja aturdido y expuesto. No enfrentar sin equipo.''',
  ),
  LoreFile(
    id: 'diario-portero',
    category: LoreCategory.diario,
    code: 'DIARIO/PT-01',
    title: 'El portero de la calle Lavalle',
    date: 'Día 7',
    author: 'Anónimo',
    unlock: LoreUnlock(UnlockStat.looted, 10),
    body: '''Don Ramón sigue barriendo la vereda todas las mañanas. Dice que si deja de hacerlo, la ciudad se termina de verdad.

Le dejé dos latas de atún en el palier. Me dio una llave del depósito del edificio "por si algún día la necesitás, pibe". Adentro había madera, clavos y una radio a pilas.''',
  ),
  LoreFile(
    id: 'corpus-nodos',
    category: LoreCategory.corpus,
    code: 'CORPUS/N',
    title: 'Nodos y suturas',
    date: 'Actualizado continuamente',
    author: 'Base de conocimiento VITA-7',
    unlock: LoreUnlock(UnlockStat.donated, 10),
    body: '''Un NODO es un refugio con antena de relevo. Cada aporte de recursos mejora su antena: más alcance, más defensas, mejor taller.

Una SUTURA es la conexión entre dos nodos. En el mapa se ve como una línea punteada que avanza. Cuando un nodo cae, la sutura se corta y su zona vuelve a quedar a oscuras.

En la bitácora de cada nodo se escribe a máquina. Es lento a propósito: obliga a quedarse quieto un rato. A recuperar el aire.''',
  ),
  LoreFile(
    id: 'fk-lote7',
    category: LoreCategory.informe,
    code: 'FK/MEMO-07',
    title: 'Memo interno: lote 7',
    date: 'Tres semanas antes del Día 1',
    author: 'Laboratorios Ferrán-Kessler, Barracas',
    stamp: 'CONFIDENCIAL',
    unlock: LoreUnlock(UnlockStat.level, 4),
    body: '''Para: Dirección Científica
Asunto: Lote 7, ensayo de cultivo fúngico AMB

Los cultivos del lote 7 muestran crecimiento fuera de la cámara de contención. ██████████ recomienda suspender el ensayo, pero la junta decide continuar por compromisos con ███████████████.

Se solicita no registrar el incidente del depósito 3 hasta nuevo aviso. Las muestras extraviadas ████ ███████ por el Riachuelo.

Destruir después de leer.''',
  ),
  LoreFile(
    id: 'diario-bruto',
    category: LoreCategory.diario,
    code: 'DIARIO/CT-02',
    title: 'Bruto en Constitución',
    date: 'Día 9',
    author: 'Martín "Gaucho" R., Enlace de Barracas',
    unlock: LoreUnlock(UnlockStat.bruteKills, 1),
    body: '''Lo vi agacharse y me acordé del informe 14. Me cubrí con el chaleco de chapa y pasó de largo como un 60 en hora pico. Se quedó tambaleando contra el kiosco.

Dos golpes con el hacha. Me temblaron las manos media hora. Hoy le mando un pulso a quien haya escrito ese informe, donde sea que esté.''',
  ),
  LoreFile(
    id: 'tx-desam-final',
    category: LoreCategory.transmision,
    code: 'TX/DESAM-FIN',
    title: 'Última transmisión de la DESAM',
    date: 'Día 9 · 23:58',
    author: 'Centro de Operaciones DESAM',
    unlock: LoreUnlock(UnlockStat.level, 6),
    body: '''A todos los Enlaces activos.

El centro de operaciones queda sin energía en minutos. Las terminales VITA-7 van a seguir funcionando sin nosotros. La red ya no depende de un edificio: depende de ustedes.

Mantengan los nodos. Compartan lo que encuentren. No dejen a nadie sin señal.

Fin de transmisión. Gracias por caminar.''',
  ),
  LoreFile(
    id: 'diario-nodo-propio',
    category: LoreCategory.diario,
    code: 'DIARIO/PROPIO',
    title: 'Mi primer nodo',
    date: 'Hoy',
    author: 'Vos',
    unlock: LoreUnlock(UnlockStat.shelters, 1),
    body: '''Monté la antena en una esquina tranquila, lejos de casa: la terminal no deja instalarla donde vivís, y está bien que así sea.

Escribí la primera línea en la bitácora. La máquina se trabó dos veces. Afuera, a lo lejos, un chillón. Adentro, por primera vez en días, silencio.''',
  ),
];
