class ParadaModel {
  final int? idParada;
  final String nombre;
  final double latitud;
  final double longitud;

  ParadaModel({
    this.idParada,
    required this.nombre,
    required this.latitud,
    required this.longitud,
  });

  // Convierte objeto → mapa (para SQLite)
  Map<String, dynamic> toMap() {
    return {
      'ID_PARADA': idParada,
      'NOMBRE': nombre,
      'LATITUD': latitud,
      'LONGITUD': longitud,
    };
  }

  // Convierte mapa SQLite → objeto
  factory ParadaModel.fromMap(Map<String, dynamic> map) {
    return ParadaModel(
      idParada: map['ID_PARADA'],
      nombre: map['NOMBRE'],
      latitud: map['LATITUD'],
      longitud: map['LONGITUD'],
    );
  }
}
