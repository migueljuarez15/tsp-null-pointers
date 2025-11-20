import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:vamonos_recio/modelos/RutaModel.dart';
import '../modelos/ParadaModel.dart';
import '../services/DatabaseHelper.dart';

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

  /// 🚍 Dibuja una ruta completa leyendo la polyline precomputada desde la BD (RUTA.POLYLINE)
  Future<void> dibujarRutaDesdeBD(int idRuta) async {
    _cargando = true;
    notifyListeners();

    try {
      // 🔹 Limpia polyline y marcadores anteriores (excepto el destino)
      _polylines.clear();
      _marcadores.removeWhere(
        (m) => m.markerId.value != "destino_buscado",
      );

      // 🔹 Consulta las paradas de la ruta ordenadas (para marcadores)
      final List<ParadaModel> paradas =
          await _db.obtenerParadasPorRuta(idRuta);

      if (paradas.isEmpty) {
        debugPrint('⚠️ No se encontraron paradas para la ruta $idRuta');
        _cargando = false;
        notifyListeners();
        return;
      }

      // 🔹 Agrega marcadores de paradas
      _marcadores.addAll(paradas.map((p) {
        return Marker(
          markerId: MarkerId('parada_${p.idParada}'),
          position: LatLng(p.latitud, p.longitud),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: p.nombre),
        );
      }));

      // 🔹 Leer polyline precomputada desde la tabla RUTA
      final polylineJson = await _db.obtenerPolylineRuta(idRuta);

      List<LatLng> rutaCompleta = [];

      if (polylineJson != null) {
        final List<dynamic> data = jsonDecode(polylineJson);
        rutaCompleta = data.map<LatLng>((p) {
          return LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          );
        }).toList();
      } else {
        // (Opcional) Fallback: si aún no hay polyline guardada, puedes usar OSRM
        debugPrint(
            '⚠️ La ruta $idRuta no tiene POLYLINE guardada. Considera correr el precompute.');
      }

      if (rutaCompleta.isEmpty) {
        debugPrint(
            '⚠️ No se pudo construir la polyline para la ruta $idRuta');
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

  // --------------------------------------------------
  // 5️⃣ Calcular ruta a pie (CU-4 - Parada más cercana)
  // --------------------------------------------------
  LatLng? _ubicacionActual;
  ParadaModel? _paradaMasCercana;
  Set<Polyline> _rutaCaminando = {};
  Set<Marker> _markers = {};
  bool _mostrandoRutaCaminando = false;
  String? _distanciaCaminando;
  String? _tiempoCaminando;
  bool _mostrarPopupCaminando = false;
  bool get mostrarPopupCaminando => _mostrarPopupCaminando;
  LatLng? get ubicacionActual => _ubicacionActual;
  ParadaModel? get paradaMasCercana => _paradaMasCercana;
  Set<Polyline> get rutaCaminando => _rutaCaminando;
  bool get mostrandoRutaCaminando => _mostrandoRutaCaminando;
  String? get distanciaCaminando => _distanciaCaminando;
  String? get tiempoCaminando => _tiempoCaminando;

  /// 📍 Establece la ubicación actual del trabajador
  void setUbicacionActual(LatLng ubicacion) {
    _ubicacionActual = ubicacion;
    notifyListeners();
  }

  /// 🔎 Obtiene la parada más cercana a la ubicación actual dentro de una ruta
  Future<void> obtenerParadaMasCercana(int idRuta) async {
    if (_ubicacionActual == null) {
      debugPrint("⚠️ No se ha definido la ubicación actual.");
      return;
    }

    try {
      final paradas = await _db.obtenerParadasPorRuta(idRuta);
      if (paradas.isEmpty) return;

      ParadaModel? masCercana;
      double minDist = double.infinity;

      for (var p in paradas) {
        final dist = _distanciaKm(
          LatLng(p.latitud, p.longitud),
          _ubicacionActual!,
        );
        if (dist < minDist) {
          minDist = dist;
          masCercana = p;
        }
      }

      _paradaMasCercana = masCercana;

      if (masCercana != null) {
        // 🔹 Añadir marcador visual
        _marcadores.add(
          Marker(
            markerId: const MarkerId("parada_mas_cercana"),
            position: LatLng(masCercana.latitud, masCercana.longitud),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: masCercana.nombre,
              snippet: "Parada más cercana",
            ),
          ),
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint("❌ Error al calcular parada más cercana: $e");
    }
  }

  Future<void> calcularRutaCaminando({
    required LatLng origen,
    required LatLng destino,
    required String apiKey,
  }) async {
    try {
      _cargando = true;
      _rutaCaminando.clear();
      notifyListeners();

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origen.latitude},${origen.longitude}&destination=${destino.latitude},${destino.longitude}&mode=walking&key=$apiKey',
      );

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final route = data['routes'][0];
        final leg = route['legs'][0];

        // 🟢 Decodificar polyline con PolylinePoints v3
        final polylinePoints = PolylinePoints(apiKey: apiKey);
        final decodedPoints = PolylinePoints.decodePolyline(route['overview_polyline']['points']);

        final List<LatLng> polylineCoords = decodedPoints
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();


        _rutaCaminando.add(Polyline(
          polylineId: const PolylineId("rutaCaminando"),
          color: const Color.fromARGB(255, 65, 105, 225), // Azul caminata
          width: 5,
          points: polylineCoords,
          patterns: [PatternItem.dot, PatternItem.gap(20)], // 🔸 Línea punteada
          geodesic: true, // suaviza las curvas
        ));

        // 🟡 Marcadores de inicio y destino
        _markers.add(Marker(
          markerId: const MarkerId("ubicacionActual"),
          position: origen,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: "Tu ubicación"),
        ));

        _markers.add(Marker(
          markerId: const MarkerId("paradaCercana"),
          position: destino,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: const InfoWindow(title: "Parada más cercana"),
        ));

        // ⏱ ETA y distancia
        _tiempoCaminando = leg['duration']['text'];
        _distanciaCaminando = leg['distance']['text'];
        _mostrarPopupCaminando = true;
      } else {
        debugPrint("Error en la API Directions (walking): ${data['status']}");
      }
    } catch (e) {
      debugPrint("Error al calcular ruta caminando: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// ❌ Limpia la ruta caminando
  void limpiarRutaCaminando() {
    _rutaCaminando.clear();
    _mostrandoRutaCaminando = false;
    _paradaMasCercana = null;
    _marcadores.removeWhere((m) => m.markerId.value == "parada_mas_cercana");
    notifyListeners();
  }

  void mostrarPopupRutaCaminando() {
    _mostrarPopupCaminando = true;
    notifyListeners();
  }

  void ocultarPopupRutaCaminando() {
    _mostrarPopupCaminando = false;
    notifyListeners();
  }
}
