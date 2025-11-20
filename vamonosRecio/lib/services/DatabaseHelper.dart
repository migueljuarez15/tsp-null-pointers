import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../modelos/ParadaModel.dart';
import '../modelos/RutaModel.dart';
import '../modelos/RecorridoModel.dart';
import '../modelos/SitioModel.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // 🔹 Nombre con el que se copiará internamente en el dispositivo
    const String dbName = 'vamonosRecioV2.db';

    // 🔹 Ruta donde se guardará la BD en el dispositivo
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    // 🔹 Verificar si ya existe la BD en el dispositivo
    final exists = await databaseExists(path);

    if (!exists) {
      print('📦 Copiando base de datos desde assets...');

      // Ruta de la BD dentro de assets
      final data = await rootBundle.load('assets/database/vamonosRecioV2.db');
      final bytes = data.buffer.asUint8List();

      // Crear directorio si no existe
      await Directory(dirname(path)).create(recursive: true);

      // Copiar el archivo
      await File(path).writeAsBytes(bytes, flush: true);

      print('✅ Base de datos copiada en $path');
    } else {
      print('✅ Base de datos ya existe en $path');
    }

    // 🔹 Abrir base de datos
    return await openDatabase(path, version: 1);
  }

  Future<List<ParadaModel>> obtenerParadas() async {
    try {
      final db = await database;
      final results = await db.query('PARADAS');
      print("🟢 Se encontraron ${results.length} paradas en la BD.");
      return results.map((mapa) => ParadaModel.fromMap(mapa)).toList();
    } catch (e) {
      print('❌ Error en obtenerParadas(): $e');
      return [];
    }
  }

  Future<List<ParadaModel>> obtenerParadasCercanas(LatLng destino, double radioMetros) async {
    final db = await database;
    final results = await db.query('PARADAS');
    final paradas = results.map((e) => ParadaModel.fromMap(e)).toList();

    const double R = 6371000; // Radio terrestre en metros
    List<ParadaModel> cercanas = [];

    for (var p in paradas) {
      final dLat = (destino.latitude - p.latitud) * (3.141592653589793 / 180);
      final dLon = (destino.longitude - p.longitud) * (3.141592653589793 / 180);
      final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(p.latitud * (3.141592653589793 / 180)) *
            cos(destino.latitude * (3.141592653589793 / 180)) *
            (sin(dLon / 2) * sin(dLon / 2));
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      final distancia = R * c;

      if (distancia <= radioMetros) cercanas.add(p);
    }

    return cercanas;
  }

  Future<List<RutaModel>> obtenerRutasPorParadas(List<int> idsParadas) async {
    if (idsParadas.isEmpty) return [];

    final db = await database;
    final idList = idsParadas.join(',');

    final results = await db.rawQuery('''
      SELECT DISTINCT R.*
      FROM RUTA R
      INNER JOIN RECORRIDO RC ON R.ID_RUTA = RC.ID_RUTA
      WHERE RC.ID_PARADA IN ($idList)
    ''');

    return results.map((e) => RutaModel.fromMap(e)).toList();
  }

  Future<List<ParadaModel>> obtenerParadasPorRuta(int idRuta) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT P.ID_PARADA, P.NOMBRE, P.LATITUD, P.LONGITUD
      FROM RECORRIDO R
      INNER JOIN PARADAS P ON R.ID_PARADA = P.ID_PARADA
      WHERE R.ID_RUTA = ?
      ORDER BY R.ORDEN ASC
    ''', [idRuta]);

    return result.map((e) => ParadaModel.fromMap(e)).toList();
  }

  Future<List<RutaModel>> obtenerRutas() async {
    final db = await database;
    final results = await db.query('RUTA');
    return results.map((mapa) => RutaModel.fromMap(mapa)).toList();
  }

  Future<List<RecorridoModel>> obtenerRecorridos() async {
    final db = await database;
    final results = await db.query('RECORRIDO');
    return results.map((mapa) => RecorridoModel.fromMap(mapa)).toList();
  }

  Future<List<SitioModel>> obtenerSitios() async {
    try {
      final db = await database;
      final results = await db.query('SITIO');
      print("🟢 Se encontraron ${results.length} sitios en la BD.");
      return results.map((mapa) => SitioModel.fromMap(mapa)).toList();
    } catch (e) {
      print('❌ Error en obtenerSitios(): $e');
      return [];
    }
  }

  /// Regresa las paradas de una ruta en el orden definido en RECORRIDO
  Future<List<ParadaModel>> obtenerParadasDeRuta(int idRuta) async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT P.ID_PARADA, P.NOMBRE, P.LATITUD, P.LONGITUD
      FROM RECORRIDO R
      JOIN PARADAS P ON P.ID_PARADA = R.ID_PARADA
      WHERE R.ID_RUTA = ?
      ORDER BY R.ORDEN ASC
    ''', [idRuta]);

    return result.map((m) => ParadaModel.fromMap(m)).toList();
  }

  /// Guarda/actualiza la polyline de una ruta
  Future<void> guardarPolylineRuta(int idRuta, String polyline) async {
    final db = await database;
    await db.update(
      'RUTA',
      {'POLYLINE': polyline},
      where: 'ID_RUTA = ?',
      whereArgs: [idRuta],
    );
  }

  /// Obtiene la polyline de una ruta (puede regresar null)
  Future<String?> obtenerPolylineRuta(int idRuta) async {
    final db = await database;

    final result = await db.query(
      'RUTA',
      columns: ['POLYLINE'],
      where: 'ID_RUTA = ?',
      whereArgs: [idRuta],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first['POLYLINE'] as String?;
  }

  /// 🔍 DEBUG: Imprime el tamaño de las polylines guardadas en tabla RUTA
Future<void> debugImprimirTamanosPolylines() async {
  final db = await database;

  final result = await db.rawQuery('''
    SELECT ID_RUTA, 
           CASE 
             WHEN POLYLINE IS NULL THEN 'NULL'
             WHEN POLYLINE = '' THEN 'VACÍO'
             ELSE LENGTH(POLYLINE) || ' bytes'
           END AS TAMANO
    FROM RUTA
    ORDER BY ID_RUTA;
  ''');

  print("📌 ====== DEBUG POLYLINES ======");
  for (final row in result) {
    print("Ruta ${row['ID_RUTA']} → Polyline: ${row['TAMANO']}");
  }
  print("📌 =============================");
}
}