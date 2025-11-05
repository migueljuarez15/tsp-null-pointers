class RutaModel {
  final int? idRuta;
  final String nombre;
  final String color;
  final String horario;
  final String tiempoEstimadoEspera;

  RutaModel({
    this.idRuta,
    required this.nombre,
    required this.color,
    required this.horario,
    required this.tiempoEstimadoEspera,
  });

  // Convierte un objeto Ruta → Mapa (para guardar en SQLite)
  Map<String, dynamic> toMap() {
    return {
      'ID_RUTA': idRuta,
      'NOMBRE': nombre,
      'COLOR': color,
      'HORARIO': horario,
      'TIEMPO_ESTIMADO_ESPERA': tiempoEstimadoEspera,
    };
  }

  // Convierte un mapa SQLite → Objeto Ruta
  factory RutaModel.fromMap(Map<String, dynamic> map) {
    return RutaModel(
      idRuta: map['ID_RUTA'],
      nombre: map['NOMBRE'],
      color: map['COLOR'],
      horario: map['HORARIO'],
      tiempoEstimadoEspera: map['TIEMPO_ESTIMADO_ESPERA'],
    );
  }
}
