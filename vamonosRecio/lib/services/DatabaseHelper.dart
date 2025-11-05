import 'dart:io';

import 'package:flutter/services.dart';
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
    const String dbName = 'vamonosRecio.db';

    // 🔹 Ruta donde se guardará la BD en el dispositivo
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    // 🔹 Verificar si ya existe la BD en el dispositivo
    final exists = await databaseExists(path);

    if (!exists) {
      print('📦 Copiando base de datos desde assets...');

      // Ruta de la BD dentro de assets
      final data = await rootBundle.load('assets/database/vamonosRecio.db');
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
}