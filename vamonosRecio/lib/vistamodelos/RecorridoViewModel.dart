import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../modelos/ParadaModel.dart';
import '../modelos/RutaModel.dart';
import '../modelos/RecorridoModel.dart';
import '../services/DatabaseHelper.dart';
import '../services/MapService.dart';

class RecorridoViewModel extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _mapService = MapService();

  bool modoCamion = true;
  bool mostrandoMensaje = true;

  Set<Polyline> polylines = {};
  Set<Circle> circles = {};
  String? mensajeTemporal;

  double _zoomActual = 13;

  /// Inicialización
  Future<void> inicializar() async {
    await cargarContenido();
    Future.delayed(const Duration(seconds: 3), () {
      mostrandoMensaje = false;
      notifyListeners();
    });
  }

  /// Alternar entre rutas y paradas
  Future<void> toggleModo() async {
    modoCamion = !modoCamion;
    mostrandoMensaje = true;
    mensajeTemporal = modoCamion
        ? "Mostrando rutas de camión 🚌"
        : "Mostrando sitios/paradas 🚕";
    notifyListeners();

    await cargarContenido();

    Future.delayed(const Duration(seconds: 3), () {
      mostrandoMensaje = false;
      notifyListeners();
    });
  }

  /// Cargar datos según modo
  Future<void> cargarContenido() async {
    if (modoCamion) {
      await cargarRutasCompletas();
    } else {
      await cargarParadasEnMapa(_zoomActual);
    }
  }

  /// Cargar todas las rutas con sus recorridos y trazarlas
  Future<void> cargarRutasCompletas() async {
    try {
      final rutas = await _db.obtenerRutas();
      final recorridos = await _db.obtenerRecorridos();
      final paradas = await _db.obtenerParadas();

      final allPolylines = <Polyline>{};
      for (final ruta in rutas) {
        final paradasRuta = recorridos
            .where((r) => r.idRuta == ruta.idRuta)
            .map((r) => paradas.firstWhere((p) => p.idParada == r.idParada))
            .toList();

        final poly = _mapService.generarPolyline(paradasRuta, ruta.color);
        allPolylines.addAll(poly);
      }

      polylines = allPolylines;
      circles.clear();
      notifyListeners();
    } catch (e) {
      debugPrint("Error cargando rutas: $e");
    }
  }

  /// Cargar paradas desde DB con optimización por zoom
  Future<void> cargarParadasEnMapa(double zoom) async {
    try {
      final paradas = await _db.obtenerParadas();
      _zoomActual = zoom;

      int maxCircles = zoom >= 16
          ? paradas.length // Zoom alto, todas
          : zoom >= 14
              ? (paradas.length / 3).round()
              : (paradas.length / 8).round();

      final paradasFiltradas =
          paradas.take(maxCircles.clamp(10, paradas.length)).toList();

      circles = paradasFiltradas.map((p) {
        return Circle(
          circleId: CircleId(p.idParada.toString()),
          center: LatLng(p.latitud, p.longitud),
          radius: 15,
          fillColor: const Color(0xFF00BCD4).withOpacity(0.5),
          strokeColor: const Color(0xFF00838F),
          strokeWidth: 2,
          onTap: () {
            mensajeTemporal = "📍 ${p.nombre}";
            mostrandoMensaje = true;
            notifyListeners();
            Future.delayed(const Duration(seconds: 2), () {
              mostrandoMensaje = false;
              notifyListeners();
            });
          },
        );
      }).toSet();

      polylines.clear();
      notifyListeners();
    } catch (e) {
      debugPrint("Error cargando paradas: $e");
    }
  }
}
