// lib/services/RoutePrecomputeService.dart
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/DatabaseHelper.dart';
import '../services/DirectionsService.dart';
import '../modelos/ParadaModel.dart';

class RoutePrecomputeService {
  final DatabaseHelper db;
  final DirectionsService directions;

  RoutePrecomputeService({
    required this.db,
    required this.directions,
  });

  /// Precomputar UNA ruta y guardar sus puntos en la tabla RUTA.POLYLINE (como JSON)
  Future<void> precomputarRuta(int idRuta) async {
    print('🚀 [RoutePrecompute] Precomputando ruta $idRuta');

    final List<ParadaModel> paradas = await db.obtenerParadasDeRuta(idRuta);
    print('   - Paradas en ruta $idRuta: ${paradas.length}');

    if (paradas.length < 2) {
      print('   ⚠️ Ruta $idRuta tiene menos de 2 paradas. Se omite.');
      return;
    }

    final List<LatLng> puntosTotales = [];

    for (int i = 0; i < paradas.length - 1; i++) {
      final origen = LatLng(paradas[i].latitud, paradas[i].longitud);
      final destino = LatLng(paradas[i + 1].latitud, paradas[i + 1].longitud);

      print('   ➜ Segmento $i: '
          '(${origen.latitude},${origen.longitude}) '
          '→ (${destino.latitude},${destino.longitude})');

      try {
        final segmento = await directions.obtenerSegmentoRuta(
          origen: origen,
          destino: destino,
          mode: 'driving', // o 'transit'
        );

        print('     · Puntos en segmento $i: ${segmento.length}');

        if (segmento.isEmpty) continue;

        // Evitar repetir el punto de unión
        for (int j = 0; j < segmento.length; j++) {
          if (i > 0 && j == 0) continue;
          puntosTotales.add(segmento[j]);
        }

        // Pequeño delay para no matar el QPS
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        print('   ❌ Error en Directions para segmento $i de ruta $idRuta: $e');
      }
    }

    print('   ✅ Total de puntos en ruta $idRuta: ${puntosTotales.length}');

    if (puntosTotales.isEmpty) {
      print('   ⚠️ No se generaron puntos para ruta $idRuta. No se guarda nada.');
      return;
    }

    // Guardamos JSON de puntos
    final polylineJson = jsonEncode(
      puntosTotales
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
    );

    await db.guardarPolylineRuta(idRuta, polylineJson);
    print('   💾 Polyline JSON guardada en BD para ruta $idRuta '
        '(longitud string: ${polylineJson.length})');

    // Verificación inmediata
    final saved = await db.obtenerPolylineRuta(idRuta);
    print('   🔍 Verificación BD ruta $idRuta → '
        'POLYLINE length: ${saved?.length ?? 0}');
  }

  /// Precomputar TODAS las rutas
  Future<void> precomputarTodasLasRutas(List<int> idsRutas) async {
    print('📦 [RoutePrecompute] Rutas a precomputar: $idsRutas');

    for (final id in idsRutas) {
      try {
        await precomputarRuta(id);
      } catch (e, st) {
        print('   ❌ Error crítico precomputando ruta $id: $e');
        print(st);
      }
    }

    print('✅ [RoutePrecompute] precomputarTodasLasRutas() terminado');
  }
}