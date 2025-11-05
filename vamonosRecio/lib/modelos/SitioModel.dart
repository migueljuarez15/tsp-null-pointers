class SitioModel {
  final int? idSitio;
  final String nombre;
  final double latitud;
  final double longitud;

  SitioModel({
    this.idSitio,
    required this.nombre,
    required this.latitud,
    required this.longitud,
  });

  // Convierte objeto → mapa (para SQLite)
  Map<String, dynamic> toMap() {
    return {
      'ID_SITIO': idSitio,
      'NOMBRE': nombre,
      'LATITUD': latitud,
      'LONGITUD': longitud,
    };
  }

  // Convierte mapa SQLite → objeto
  factory SitioModel.fromMap(Map<String, dynamic> map) {
    return SitioModel(
      idSitio: map['ID_SITIO'],
      nombre: map['NOMBRE'],
      latitud: map['LATITUD'],
      longitud: map['LONGITUD'],
    );
  }
}