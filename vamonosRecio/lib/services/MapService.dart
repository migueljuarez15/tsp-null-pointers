// MapService.dart
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vamonos_recio/services/DatabaseHelper.dart';
import '../modelos/ParadaModel.dart';
import 'package:flutter/material.dart';

class MapService {

  // Límite geográfico aproximado de Zacatecas–Guadalupe
  static final LatLngBounds zonaMetropolitanaBounds = LatLngBounds(
    southwest: const LatLng(22.68, -102.65),
    northeast: const LatLng(22.85, -102.45),
  );

  // Centro del mapa
  static final LatLng centroZacatecas = const LatLng(22.77, -102.57);

  final _db = DatabaseHelper();

  // Genera una Polyline con color y puntos del recorrido
  Set<Polyline> generarPolyline(List<ParadaModel> paradas, String colorHex) {
    final color = _parseColor(colorHex);
    return {
      Polyline(
        polylineId: const PolylineId("recorrido"),
        color: color,
        width: 5,
        points: paradas
            .map((p) => LatLng(p.latitud, p.longitud))
            .toList(),
      ),
    };
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    return Color(int.parse("0xFF$hexColor"));
  }

  // Validar si un punto está dentro de la zona metropolitana
  bool estaDentroDeZona(double lat, double lon) {
    return lat >= zonaMetropolitanaBounds.southwest.latitude &&
        lat <= zonaMetropolitanaBounds.northeast.latitude &&
        lon >= zonaMetropolitanaBounds.southwest.longitude &&
        lon <= zonaMetropolitanaBounds.northeast.longitude;
  }

  /// 🔹 Obtiene paradas optimizadas desde BD según zoom
  static Future<Set<Circle>> obtenerParadasOptimizado(double zoom) async {
    final db = DatabaseHelper();
    final paradas = await db.obtenerParadas();

    if (paradas.isEmpty) return {};

    int maxCircles = zoom >= 16
        ? paradas.length // Zoom alto → todas
        : zoom >= 14
            ? (paradas.length / 3).round()
            : (paradas.length / 8).round();

    // Filtramos aleatoriamente para no saturar
    final random = Random();
    final paradasFiltradas = (paradas.toList()..shuffle(random))
        .take(maxCircles)
        .toList();

    return paradasFiltradas.map((p) {
      return Circle(
        circleId: CircleId(p.nombre),
        center: LatLng(p.latitud, p.longitud),
        radius: 15,
        fillColor: Colors.teal.withOpacity(0.5),
        strokeColor: Colors.teal.shade900,
        strokeWidth: 2,
      );
    }).toSet();
  }

  static Color _colorDesdeHex(String hex) {
    hex = hex.replaceAll("#", "");
    if (hex.length == 6) hex = "FF$hex";
    return Color(int.parse("0x$hex"));
  }
}