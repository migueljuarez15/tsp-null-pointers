import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vamonos_recio/modelos/SitioModel.dart';
import 'package:vamonos_recio/services/DatabaseHelper.dart';

class SitioViewModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<SitioModel> _sitios = [];
  SitioModel? _sitioMasCercano;
  LatLng? _ubicacionActual;
  LatLng? _destinoSeleccionado;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  String? _tiempoEstimado;
  String? _distanciaAprox;

  bool _cargando = false;

  // Getters públicos
  List<SitioModel> get sitios => _sitios;
  SitioModel? get sitioMasCercano => _sitioMasCercano;
  Set<Marker> get markers => _markers;
  Set<Polyline> get polylines => _polylines;
  String? get tiempoEstimado => _tiempoEstimado;
  String? get distanciaAprox => _distanciaAprox;
  bool get cargando => _cargando;

  // Asigna ubicaciones
  void setUbicacionActual(LatLng ubicacion) {
    _ubicacionActual = ubicacion;
    notifyListeners();
  }

  void setDestinoSeleccionado(LatLng destino) {
    _destinoSeleccionado = destino;
    notifyListeners();
  }

  // --------------------------------------------------
  // 1️⃣ Cargar sitios desde BD local
  // --------------------------------------------------
  Future<void> cargarSitios() async {
    _sitios = await _db.obtenerSitios();
    notifyListeners();
  }

  // --------------------------------------------------
  // 2️⃣ Buscar el sitio de taxis más cercano
  // --------------------------------------------------
  Future<SitioModel?> obtenerSitioMasCercano(LatLng origen) async {
    if (_sitios.isEmpty) await cargarSitios();

    double minDist = double.infinity;
    SitioModel? sitioMasCercanoTemp;

    for (var sitio in _sitios) {
      final distancia = _calcularDistancia(origen, LatLng(sitio.latitud, sitio.longitud));
      if (distancia < minDist) {
        minDist = distancia;
        sitioMasCercanoTemp = sitio;
      }
    }

    _sitioMasCercano = sitioMasCercanoTemp;
    notifyListeners();
    return _sitioMasCercano;
  }

  // --------------------------------------------------
  // 3️⃣ Calcular la ruta taxi usando Google Directions API
  // --------------------------------------------------
  Future<void> calcularRutaTaxi({
    required LatLng origen,
    required LatLng destino,
    required String apiKey,
  }) async {
    try {
      _cargando = true;
      _markers.clear();
      _polylines.clear();
      notifyListeners();

      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origen.latitude},${origen.longitude}&destination=${destino.latitude},${destino.longitude}&mode=driving&key=$apiKey');

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final route = data['routes'][0];
        final leg = route['legs'][0];

        // 🟡 Polyline
        final polylinePoints = PolylinePoints(apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8');
        final decodedPoints = PolylinePoints.decodePolyline(route['overview_polyline']['points']);
        final List<LatLng> polylineCoords = decodedPoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        _polylines.add(Polyline(
          polylineId: const PolylineId("taxiRoute"),
          color: const Color.fromARGB(255, 255, 96, 96),
          width: 6,
          points: polylineCoords,
        ));

        // 🟢 Marcadores
        if (_sitioMasCercano != null) {
          _markers.add(Marker(
            markerId: const MarkerId("sitioMasCercano"),
            position: LatLng(_sitioMasCercano!.latitud, _sitioMasCercano!.longitud),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(
              title: _sitioMasCercano!.nombre,
              snippet: "Sitio más cercano",
            ),
          ));
        }

        _markers.add(Marker(
          markerId: const MarkerId("destino"),
          position: destino,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destino seleccionado"),
        ));

        // ⏱ ETA y distancia
        _tiempoEstimado = leg['duration']['text'];
        _distanciaAprox = leg['distance']['text'];
      } else {
        debugPrint("Error en la API Directions: ${data['status']}");
      }
    } catch (e) {
      debugPrint("Error al calcular ruta taxi: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------
  // 4️⃣ Limpiar mapa
  // --------------------------------------------------
  void limpiarMapaTaxi() {
    _markers.clear();
    _polylines.clear();
    _tiempoEstimado = null;
    _distanciaAprox = null;
    _sitioMasCercano = null;
    notifyListeners();
  }

  // --------------------------------------------------
  // 🔹 Utilidad: Calcular distancia entre dos puntos
  // --------------------------------------------------
  double _calcularDistancia(LatLng p1, LatLng p2) {
    const R = 6371; // km
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLng = _toRadians(p2.longitude - p1.longitude);
    final a = 
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(p1.latitude)) *
            cos(_toRadians(p2.latitude)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * (3.141592653589793 / 180);
  }
}