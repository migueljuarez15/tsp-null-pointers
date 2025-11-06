import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/DatabaseHelper.dart';
import '../services/LocationService.dart';
import '../modelos/ParadaModel.dart';
import '../modelos/SitioModel.dart';
import '../services/MapService.dart';

class HomeViewModel extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _locationService = LocationService();

  bool mostrarParadas = true;
  Set<Marker> marcadores = {};
  Set<Polyline> polylines = {};
  LatLng? ubicacionActual;
  LatLng? destinoSeleccionado;
  bool cargando = true;

  HomeViewModel() {
    inicializarMapa();
  }

  /// Inicializa mapa y obtiene ubicación actual
  Future<void> inicializarMapa() async {
    cargando = true;
    notifyListeners();

    try {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null) {
        ubicacionActual = LatLng(loc.latitude, loc.longitude);
      }
    } catch (e) {
      debugPrint("Error al inicializar mapa: $e");
    }

    cargando = false;
    notifyListeners();
  }

  // 🔹 Calcula distancia entre dos coordenadas
  double _distanciaEntre(LatLng a, LatLng b) {
    const R = 6371; // Radio terrestre en km
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;

    final aVal = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
    return R * c;
  }

  // 🔸 Encuentra la parada más cercana a un punto dado
  Future<ParadaModel?> obtenerParadaMasCercana(LatLng punto) async {
    final paradas = await _db.obtenerParadas();
    ParadaModel? masCercana;
    double menorDistancia = double.infinity;

    for (var p in paradas) {
      final distancia =
          _distanciaEntre(punto, LatLng(p.latitud, p.longitud));
      if (distancia < menorDistancia) {
        menorDistancia = distancia;
        masCercana = p;
      }
    }
    return masCercana;
  }

  // 🔹 Dibuja ruta realista (Polyline) entre ubicaciones/paradas
  Future<void> dibujarRutaHaciaDestino(LatLng destino) async {
    if (ubicacionActual == null) return;

    // 1️⃣ Parada más cercana al usuario
    final paradaInicio = await obtenerParadaMasCercana(ubicacionActual!);
    // 2️⃣ Parada más cercana al destino
    final paradaDestino = await obtenerParadaMasCercana(destino);

    if (paradaInicio == null || paradaDestino == null) return;

    // 3️⃣ Simular polyline (entre las paradas y ubicaciones)
    final List<LatLng> puntos = [
      ubicacionActual!,
      LatLng(
        (ubicacionActual!.latitude + paradaInicio.latitud) / 2,
        (ubicacionActual!.longitude + paradaInicio.longitud) / 2,
      ),
      LatLng(paradaInicio.latitud, paradaInicio.longitud),
      LatLng(
        (paradaInicio.latitud + paradaDestino.latitud) / 2,
        (paradaInicio.longitud + paradaDestino.longitud) / 2,
      ),
      LatLng(paradaDestino.latitud, paradaDestino.longitud),
      LatLng(
        (paradaDestino.latitud + destino.latitude) / 2,
        (paradaDestino.longitud + destino.longitude) / 2,
      ),
      destino,
    ];

    marcadores = {
    Marker(
      markerId: const MarkerId("parada_destino"),
      position: LatLng(paradaDestino.latitud, paradaDestino.longitud),
      infoWindow: InfoWindow(
        title: "🚏 Parada cercana destino",
        snippet: "${paradaDestino.nombre} (ID: ${paradaDestino.idParada})",
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
    ),
    Marker(
      markerId: const MarkerId("destino"),
      position: destino,
      infoWindow: const InfoWindow(title: "🎯 Destino"),
    ),
  };

    polylines = {
      Polyline(
        polylineId: const PolylineId("ruta_realista"),
        color: Colors.blueAccent,
        width: 5,
        points: puntos,
      ),
    };
    notifyListeners();
  }

  //Taxis
  // 🔸 Encuentra el sitio más cercano a la ubicación actual
Future<SitioModel?> obtenerSitioMasCercano() async {
  if (ubicacionActual == null) return null;

  final sitios = await _db.obtenerSitios();
  SitioModel? masCercano;
  double menorDistancia = double.infinity;

  for (var s in sitios) {
    final distancia = _distanciaEntre(
      ubicacionActual!,
      LatLng(s.latitud, s.longitud),
    );
    if (distancia < menorDistancia) {
      menorDistancia = distancia;
      masCercano = s;
    }
  }

  return masCercano;
}

}