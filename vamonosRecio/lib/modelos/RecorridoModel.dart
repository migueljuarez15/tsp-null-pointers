class RecorridoModel {
  // ID propio de la tabla de relación (opcional, pero buena práctica)
  //final int? idRecorrido; 
  
  // Clave foránea que apunta a RUTA
  final int? idRuta;
  
  // Clave foránea que apunta a PARADAS
  final int? idParada;
  
  // Atributo propio de la relación
  final int orden;

  RecorridoModel({
    //this.idRecorrido,
    this.idRuta,
    this.idParada,
    required this.orden,
  });

  // Convierte objeto → mapa (para SQLite)
  Map<String, dynamic> toMap() {
    return {
      //'id_recorrido': idRecorrido,
      'ID_RUTA': idRuta,
      'ID_PARADA': idParada,
      'ORDEN': orden,
    };
  }

  // Convierte mapa SQLite → objeto
  factory RecorridoModel.fromMap(Map<String, dynamic> map) {
    return RecorridoModel(
      //idRecorrido: map['id_recorrido'],
      idRuta: map['ID_RUTA'],
      idParada: map['ID_PARADA'],
      orden: map['ORDEN'],
    );
  }
}