import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vamonos_recio/modelos/RutaModel.dart';
import '../modelos/ParadaModel.dart';
import '../services/DatabaseHelper.dart';
import '../services/OsrmService.dart';

class RecorridoViewModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  Set<Polyline> _polylines = {};
  Set<Marker> _marcadores = {};
  LatLng? _destinoSeleccionado;
  List<RutaModel> _rutasCandidatas = [];

  Set<Polyline> get polylines => _polylines;
  Set<Marker> get marcadores => _marcadores;
  List<RutaModel> get rutasCandidatas => _rutasCandidatas;

  bool _cargando = false;
  bool get cargando => _cargando;

  /// 🎨 Colores personalizados para rutas
  final Map<int, Color> coloresRutas = {
    1: const Color.fromARGB(255, 133, 205, 238),
    2: const Color.fromARGB(255, 8, 83, 0),
    3: const Color.fromARGB(255, 114, 114, 114),
    4: const Color.fromARGB(255, 54, 54, 248),
    8: const Color.fromARGB(255, 223, 104, 0),
    14: const Color.fromARGB(255, 219, 166, 32),
    15: const Color.fromARGB(255, 129, 0, 129),
    16: const Color.fromARGB(255, 214, 214, 34),
    17: const Color.fromARGB(255, 48, 199, 53),
    21: const Color.fromARGB(255, 255, 0, 0)
  };

  /// 📍 Marca el destino en el mapa
  void marcarDestino(LatLng destino) {
    _destinoSeleccionado = destino;
    _marcadores.removeWhere((m) => m.markerId.value == "destino_buscado");
    _marcadores.add(
      Marker(
        markerId: const MarkerId("destino_buscado"),
        position: destino,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Destino buscado"),
      ),
    );
    notifyListeners();
  }

  /// 🚍 Dibuja una ruta completa desde la BD (RECORRIDO)
  Future<void> dibujarRutaDesdeBD(int idRuta) async {
    _cargando = true;
    notifyListeners();

    try {
      // 🔹 Limpia polyline y marcadores anteriores (excepto el destino)
      _polylines.clear();
      _marcadores.removeWhere(
          (m) => m.markerId.value != "destino_buscado"); // limpia todo menos destino

      // 🔹 Consulta las paradas de la ruta ordenadas
      final List<ParadaModel> paradas = await _db.obtenerParadasPorRuta(idRuta);
      if (paradas.isEmpty) {
        debugPrint('⚠️ No se encontraron paradas para la ruta $idRuta');
        _cargando = false;
        notifyListeners();
        return;
      }

      // 🔹 Agrega marcadores solo de esa ruta
      _marcadores.addAll(paradas.map((p) {
        return Marker(
          markerId: MarkerId('parada_${p.idParada}'),
          position: LatLng(p.latitud, p.longitud),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: p.nombre),
        );
      }));

      // 🔹 Construye la polyline completa uniendo cada par de paradas consecutivas
      List<LatLng> rutaCompleta = [];
      for (int i = 0; i < paradas.length - 1; i++) {
        final origen = LatLng(paradas[i].latitud, paradas[i].longitud);
        final destino = LatLng(paradas[i + 1].latitud, paradas[i + 1].longitud);
        final segmento = await OSRMService.obtenerRutaOSRM(origen, destino);

        if (segmento.isNotEmpty) {
          if (rutaCompleta.isNotEmpty) segmento.removeAt(0);
          rutaCompleta.addAll(segmento);
        }
      }

      if (rutaCompleta.isEmpty) {
        debugPrint('⚠️ No se pudo construir la polyline para la ruta $idRuta');
        _cargando = false;
        notifyListeners();
        return;
      }

      // 🔹 Color según la ruta
      final colorRuta = coloresRutas[idRuta] ?? Colors.blueGrey;

      // 🔹 Agrega la polyline principal al mapa
      _polylines.add(
        Polyline(
          polylineId: PolylineId('ruta_$idRuta'),
          points: rutaCompleta,
          color: colorRuta,
          width: 6,
        ),
      );

      notifyListeners();
    } catch (e) {
      debugPrint("❌ Error al dibujar ruta desde BD: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// 🚿 Limpieza completa del mapa (rutas, marcadores, destino, rutas candidatas)
  void resetearTodo() {
    _polylines.clear();
    _marcadores.clear();
    _rutasCandidatas.clear();
    _destinoSeleccionado = null;
    notifyListeners();
  }

  /// 🔍 Buscar rutas que pasen cerca del destino (radio dinámico)
  Future<void> buscarRutasCercanas(LatLng destino) async {
    try {
      _cargando = true;
      notifyListeners();

      double radio = _determinarRadio(destino);
      final paradasCercanas = await _db.obtenerParadasCercanas(destino, radio);

      if (paradasCercanas.isEmpty) {
        debugPrint('❌ No hay paradas cercanas al destino');
        _rutasCandidatas = [];
        _cargando = false;
        notifyListeners();
        return;
      }

      final idsParadas = paradasCercanas.map((p) => p.idParada!).toList();
      final rutas = await _db.obtenerRutasPorParadas(idsParadas);

      _rutasCandidatas = rutas;
      notifyListeners();
    } catch (e) {
      debugPrint("⚠️ Error al buscar rutas cercanas: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// 📏 Radio dinámico según zona (urbana o lejana)
  double _determinarRadio(LatLng punto) {
    // Centro Zacatecas aproximado
    const centro = LatLng(22.7709, -102.5832);
    final distancia = _distanciaKm(punto, centro);

    if (distancia < 3.0) return 250; // zona centro
    if (distancia < 7.0) return 400; // semiurbana
    return 700; // zona lejana (Campus, etc.)
  }

  double _distanciaKm(LatLng a, LatLng b) {
    const R = 6371;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final aHarv = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1) * cos(lat2) * (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(aHarv), sqrt(1 - aHarv));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  /// 🔁 Limpia todo del mapa
  void limpiarMapa() {
    _polylines.clear();
    _marcadores.clear();
    _rutasCandidatas.clear();
    _destinoSeleccionado = null;
    notifyListeners();
  }
}
