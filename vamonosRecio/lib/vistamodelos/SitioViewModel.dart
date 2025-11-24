import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import 'package:vamonos_recio/modelos/SitioModel.dart';
import 'package:vamonos_recio/services/DatabaseHelper.dart';
import 'package:vamonos_recio/services/LocationService.dart';

class SitioViewModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final LocationService _locationService = LocationService();

  List<SitioModel> _sitios = [];
  SitioModel? _sitioMasCercano;
  LatLng? _ubicacionActual;
  LatLng? _destinoSeleccionado;

  bool mostrarPopupTaxiCaminando = false;
  String? tiempoCaminando;
  String? distanciaCaminando;

  Set<Marker> _markers = {};
  Set<Polyline> _polylineTaxi = {};
  List<LatLng> _polylineTaxiPuntos = [];        // 👉 puntos de la ruta del taxi (CU-7)
  Set<Polyline> _polylineCaminando = {};
  List<LatLng> _polylineCaminandoPuntos = [];   // 👉 puntos de la ruta caminando (CU-9)

  String? _tiempoEstimado;
  String? _distanciaAprox;

  bool _cargando = false;

  // 🔁 Seguimiento en vivo CU-9 (a pie al sitio)
  Timer? _timerSeguimientoTaxi;
  bool _seguimientoTaxiActivo = false;
  bool get seguimientoTaxiActivo => _seguimientoTaxiActivo;

  bool _llegoAutomaticamenteTaxi = false;
  bool get llegoAutomaticamenteTaxi => _llegoAutomaticamenteTaxi;

  // 🔁 Seguimiento en vivo CU-7 (trayecto dentro del taxi)
  Timer? _timerSeguimientoTrayectoTaxi;
  bool _seguimientoTrayectoTaxiActivo = false;
  bool get seguimientoTrayectoTaxiActivo => _seguimientoTrayectoTaxiActivo;

  bool _llegoAutomaticamenteDestinoTaxi = false;
  bool get llegoAutomaticamenteDestinoTaxi => _llegoAutomaticamenteDestinoTaxi;

  // ⚠️ Error de Google Maps API
  String? _errorApiGoogle;
  String? get errorApiGoogle => _errorApiGoogle;

  void limpiarErrorApi() {
    _errorApiGoogle = null;
    notifyListeners();
  }

  // 📍 Getters públicos
  List<SitioModel> get sitios => _sitios;
  SitioModel? get sitioMasCercano => _sitioMasCercano;
  Set<Marker> get markers => _markers;
  Set<Polyline> get polylines => {..._polylineTaxi, ..._polylineCaminando};
  String? get tiempoEstimado => _tiempoEstimado;
  String? get distanciaAprox => _distanciaAprox;
  bool get cargando => _cargando;
  LatLng? get ubicacionActual => _ubicacionActual;

  // 📍 Setters públicos
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
      final distancia = _calcularDistancia(
        origen,
        LatLng(sitio.latitud, sitio.longitud),
      );
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
      _errorApiGoogle = null; // 👈 limpiamos error previo
      _markers.clear();
      _polylineTaxi.clear(); // solo limpia las rutas de taxi, no las caminatas
      _polylineTaxiPuntos.clear();
      notifyListeners();

      _ubicacionActual = origen;
      _destinoSeleccionado = destino;

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origen.latitude},${origen.longitude}'
        '&destination=${destino.latitude},${destino.longitude}'
        '&mode=driving&key=$apiKey',
      );

      final response = await http.get(url);

      // 🚨 Error HTTP
      if (response.statusCode != 200) {
        _errorApiGoogle =
            "Google Maps está experimentando problemas (código ${response.statusCode}). "
            "Algunos datos pueden no mostrarse o ser inconsistentes.";
        notifyListeners();
        return;
      }

      final data = json.decode(response.body);

      // 🚨 Error lógico de la API (ZERO_RESULTS, OVER_QUERY_LIMIT, etc.)
      if (data['status'] != 'OK') {
        _errorApiGoogle =
            "Google Maps está experimentando problemas (${data['status']}). "
            "Algunos datos pueden no mostrarse o ser inconsistentes.";
        debugPrint("❌ Error en Directions API: ${data['status']}");
        notifyListeners();
        return;
      }

      final route = data['routes'][0];
      final leg = route['legs'][0];

      // 🟡 Decodificar polyline
      final decodedPoints =
          PolylinePoints.decodePolyline(route['overview_polyline']['points']);
      final List<LatLng> polylineCoords =
          decodedPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

      // 👉 guardamos puntos de la ruta del taxi para poder "consumirlos"
      _polylineTaxiPuntos = polylineCoords;

      _polylineTaxi.add(
        Polyline(
          polylineId: const PolylineId("taxiRoute"),
          color: const Color.fromARGB(255, 255, 96, 96),
          width: 6,
          points: polylineCoords,
        ),
      );

      // 🟢 Marcadores
      if (_sitioMasCercano != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId("sitioMasCercano"),
            position: LatLng(
              _sitioMasCercano!.latitud,
              _sitioMasCercano!.longitud,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
            infoWindow: InfoWindow(
              title: _sitioMasCercano!.nombre,
              snippet: "Sitio más cercano",
            ),
          ),
        );
      }

      _markers.add(
        Marker(
          markerId: const MarkerId("destino"),
          position: destino,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: "Destino seleccionado"),
        ),
      );

      // ⏱ ETA y distancia (iniciales)
      _tiempoEstimado = leg['duration']['text'];
      _distanciaAprox = leg['distance']['text'];
    } catch (e) {
      _errorApiGoogle =
          "Google Maps está experimentando problemas. Algunos datos pueden no mostrarse o ser inconsistentes.";
      debugPrint("⚠️ Error al calcular ruta taxi: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------
  // 4️⃣ Limpiar mapa (usado por el botón "X")
  // --------------------------------------------------
  void limpiarMapaTaxi() {
    _markers.clear();
    _polylineCaminando.clear();
    _polylineCaminandoPuntos.clear();
    _polylineTaxi.clear();
    _polylineTaxiPuntos.clear();
    _tiempoEstimado = null;
    _distanciaAprox = null;
    _sitioMasCercano = null;
    _ubicacionActual = null;
    _destinoSeleccionado = null;
    _errorApiGoogle = null; // 👈 limpiamos error también

    _timerSeguimientoTaxi?.cancel();
    _timerSeguimientoTaxi = null;
    _seguimientoTaxiActivo = false;
    _llegoAutomaticamenteTaxi = false;

    _timerSeguimientoTrayectoTaxi?.cancel();
    _timerSeguimientoTrayectoTaxi = null;
    _seguimientoTrayectoTaxiActivo = false;
    _llegoAutomaticamenteDestinoTaxi = false;

    tiempoCaminando = null;
    distanciaCaminando = null;

    notifyListeners();
  }

  // --------------------------------------------------
  // 🔹 Calcular distancia entre dos puntos
  // --------------------------------------------------
  double _calcularDistancia(LatLng p1, LatLng p2) {
    const R = 6371; // km
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLng = _toRadians(p2.longitude - p1.longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(p1.latitude)) *
            cos(_toRadians(p2.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // km
  }

  double _toRadians(double degree) => degree * (pi / 180);

  double _distanciaMetros(LatLng a, LatLng b) {
    return _calcularDistancia(a, b) * 1000.0;
  }

  // --------------------------------------------------
  // 5️⃣ Calcular ruta a pie hacia el sitio más cercano (CU-5 + CU-9)
  // --------------------------------------------------
  Future<void> calcularRutaCaminandoAlSitio({
    required LatLng origen,
    required String apiKey,
  }) async {
    try {
      _cargando = true;
      _errorApiGoogle = null; // 👈 limpiamos error previo
      _polylineCaminando.clear();
      _polylineCaminandoPuntos.clear();
      notifyListeners();

      // Verificamos que haya sitio más cercano
      if (_sitioMasCercano == null) {
        await obtenerSitioMasCercano(origen);
        if (_sitioMasCercano == null) {
          debugPrint("❌ No se encontró sitio de taxis cercano.");
          return;
        }
      }

      final destino = LatLng(
        _sitioMasCercano!.latitud,
        _sitioMasCercano!.longitud,
      );

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origen.latitude},${origen.longitude}'
        '&destination=${destino.latitude},${destino.longitude}'
        '&mode=walking'
        '&key=$apiKey',
      );

      final response = await http.get(url);

      // 🚨 Error HTTP
      if (response.statusCode != 200) {
        _errorApiGoogle =
            "Google Maps está experimentando problemas (código ${response.statusCode}). "
            "Algunos datos pueden no mostrarse o ser inconsistentes.";
        notifyListeners();
        return;
      }

      final data = json.decode(response.body);

      // 🚨 Error lógico de API
      if (data['status'] != 'OK') {
        _errorApiGoogle =
            "Google Maps está experimentando problemas (${data['status']}). "
            "Algunos datos pueden no mostrarse o ser inconsistentes.";
        debugPrint("❌ Error Directions API (walking): ${data['status']}");
        notifyListeners();
        return;
      }

      final route = data['routes'][0];
      final leg = route['legs'][0];

      // 🔵 Decodificar polyline
      final decodedPoints =
          PolylinePoints.decodePolyline(route['overview_polyline']['points']);
      final List<LatLng> coords =
          decodedPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

      // 👉 Guardamos todos los puntos para poder "consumir" la ruta
      _polylineCaminandoPuntos = coords;

      _polylineCaminando.clear();
      _polylineCaminando.add(
        Polyline(
          polylineId: const PolylineId("walkingToTaxiSite"),
          color: Colors.blueAccent,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          points: coords,
        ),
      );

      // 🟢 Marcadores
      _markers.add(
        Marker(
          markerId: const MarkerId("origenCaminandoTaxi"),
          position: origen,
          infoWindow: const InfoWindow(title: "Tú estás aquí"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId("sitioMasCercanoCaminando"),
          position: destino,
          infoWindow: InfoWindow(
            title: _sitioMasCercano!.nombre,
            snippet: "Sitio más cercano",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );

      // ⏱ ETA y distancia
      tiempoCaminando = leg['duration']['text'];
      distanciaCaminando = leg['distance']['text'];

      mostrarPopupTaxiCaminando = true;
    } catch (e) {
      _errorApiGoogle =
          "Google Maps está experimentando problemas. Algunos datos pueden no mostrarse o ser inconsistentes.";
      debugPrint("⚠️ Error al calcular ruta caminando al sitio: $e");
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// 🔄 Actualiza la polyline de caminata mostrando solo el tramo restante (CU-9)
  void _actualizarPolylineTaxiConProgreso() {
    if (_ubicacionActual == null || _polylineCaminandoPuntos.isEmpty) return;

    int indexMasCercano = 0;
    double minDist = double.infinity;

    for (int i = 0; i < _polylineCaminandoPuntos.length; i++) {
      final d =
          _distanciaMetros(_ubicacionActual!, _polylineCaminandoPuntos[i]);
      if (d < minDist) {
        minDist = d;
        indexMasCercano = i;
      }
    }

    final restantes = _polylineCaminandoPuntos.sublist(indexMasCercano);

    _polylineCaminando.clear();

    if (restantes.length > 1) {
      _polylineCaminando.add(
        Polyline(
          polylineId: const PolylineId("walkingToTaxiSite"),
          color: Colors.blueAccent,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          points: restantes,
        ),
      );
    }
  }

  /// 🔄 Actualiza la polyline del taxi mostrando solo el tramo restante (CU-7)
  void _actualizarPolylineTrayectoTaxiConProgreso() {
    if (_ubicacionActual == null || _polylineTaxiPuntos.isEmpty) return;

    int indexMasCercano = 0;
    double minDist = double.infinity;

    for (int i = 0; i < _polylineTaxiPuntos.length; i++) {
      final d =
          _distanciaMetros(_ubicacionActual!, _polylineTaxiPuntos[i]);
      if (d < minDist) {
        minDist = d;
        indexMasCercano = i;
      }
    }

    final restantes = _polylineTaxiPuntos.sublist(indexMasCercano);

    _polylineTaxi.clear();

    if (restantes.length > 1) {
      _polylineTaxi.add(
        Polyline(
          polylineId: const PolylineId("taxiRoute"),
          color: const Color.fromARGB(255, 255, 96, 96),
          width: 6,
          points: restantes,
        ),
      );
    }
  }

  /// 🔁 Recalcula la ruta caminando desde la posición actual hasta el sitio (CU-9)
  Future<void> _recalcularRutaCaminandoDesdePosicionActual(
    String apiKey,
    LatLng destinoSitio,
  ) async {
    if (_ubicacionActual == null) return;

    await calcularRutaCaminandoAlSitio(
      origen: _ubicacionActual!,
      apiKey: apiKey,
    );
  }

  /// 🔁 Recalcula la ruta del taxi desde la posición actual hasta el destino (CU-7)
  Future<void> _recalcularRutaTaxiDesdePosicionActual(String apiKey) async {
    if (_ubicacionActual == null || _destinoSeleccionado == null) return;

    await calcularRutaTaxi(
      origen: _ubicacionActual!,
      destino: _destinoSeleccionado!,
      apiKey: apiKey,
    );
  }

  // ▶️ Iniciar seguimiento a pie hacia el sitio de taxis (CU-9)
  Future<void> iniciarSeguimientoAPieSitioTaxi({
    required String apiKey,
  }) async {
    if (_sitioMasCercano == null) {
      debugPrint("⚠️ No hay sitio más cercano definido para seguimiento.");
      return;
    }

    _seguimientoTaxiActivo = true;
    _llegoAutomaticamenteTaxi = false;
    notifyListeners();

    // Ubicación inicial
    final posInicial = await _locationService.getCurrentLocation();
    if (posInicial != null) {
      _ubicacionActual = LatLng(posInicial.latitude, posInicial.longitude);
    }

    final destinoSitio = LatLng(
      _sitioMasCercano!.latitud,
      _sitioMasCercano!.longitud,
    );

    _timerSeguimientoTaxi?.cancel();

    _timerSeguimientoTaxi = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!_seguimientoTaxiActivo) return;

        final pos = await _locationService.getCurrentLocation();
        if (!_seguimientoTaxiActivo) return;
        if (pos == null) return;

        _ubicacionActual = LatLng(pos.latitude, pos.longitude);

        // Distancia directa al sitio
        final distMetros =
            _distanciaMetros(_ubicacionActual!, destinoSitio);
        distanciaCaminando = "${distMetros.toStringAsFixed(0)} m";

        // Tiempo estimado (1.4 m/s ≈ 5 km/h)
        const velocidadMedia = 1.4;
        final segundos = distMetros / velocidadMedia;
        final minutos = (segundos / 60).round();
        tiempoCaminando = "$minutos min";

        // 1️⃣ Consumir polyline si vamos sobre la ruta
        if (_polylineCaminandoPuntos.isNotEmpty) {
          final distALinea = _distanciaMetros(
            _ubicacionActual!,
            _polylineCaminandoPuntos.first,
          );

          // 2️⃣ Desvío fuerte de la ruta (> 30 m): recalcular
          if (distALinea > 30) {
            await _recalcularRutaCaminandoDesdePosicionActual(
              apiKey,
              destinoSitio,
            );
          } else {
            _actualizarPolylineTaxiConProgreso();
          }
        }

        // 3️⃣ Llegada automática (≤ 5 m)
        if (distMetros <= 5) {
          debugPrint("✅ Llegaste al sitio de taxis más cercano.");
          await detenerSeguimientoAPieSitioTaxi(porLlegadaAuto: true);
        }

        notifyListeners();
      },
    );
  }

  /// ⏹ Detener seguimiento a pie (CU-9)
  Future<void> detenerSeguimientoAPieSitioTaxi({
    bool porLlegadaAuto = false,
  }) async {
    _timerSeguimientoTaxi?.cancel();
    _timerSeguimientoTaxi = null;

    _seguimientoTaxiActivo = false;

    if (porLlegadaAuto) {
      _llegoAutomaticamenteTaxi = true;
    }

    notifyListeners();
  }

  // ▶️ Iniciar seguimiento del trayecto dentro del taxi (CU-7)
  Future<void> iniciarSeguimientoTrayectoTaxi({
    required String apiKey,
  }) async {
    if (_destinoSeleccionado == null) {
      debugPrint("⚠️ No hay destino de taxi definido para seguimiento.");
      return;
    }

    _seguimientoTrayectoTaxiActivo = true;
    _llegoAutomaticamenteDestinoTaxi = false;
    notifyListeners();

    // Ubicación inicial (donde va el taxi ahora)
    final posInicial = await _locationService.getCurrentLocation();
    if (posInicial != null) {
      _ubicacionActual = LatLng(posInicial.latitude, posInicial.longitude);
    }

    final destinoFinal = _destinoSeleccionado!;

    _timerSeguimientoTrayectoTaxi?.cancel();

    _timerSeguimientoTrayectoTaxi = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!_seguimientoTrayectoTaxiActivo) return;

        final pos = await _locationService.getCurrentLocation();
        if (!_seguimientoTrayectoTaxiActivo) return;
        if (pos == null) return;

        _ubicacionActual = LatLng(pos.latitude, pos.longitude);

        // Distancia directa al destino
        final distMetros =
            _distanciaMetros(_ubicacionActual!, destinoFinal);
        _distanciaAprox = "${distMetros.toStringAsFixed(0)} m";

        // Tiempo estimado de llegada en taxi (~ 36 km/h = 10 m/s)
        const velocidadAuto = 10.0;
        final segundos = distMetros / velocidadAuto;
        final minutos = (segundos / 60).round();
        _tiempoEstimado = "$minutos min";

        // 1️⃣ Consumir polyline si vamos sobre la ruta
        if (_polylineTaxiPuntos.isNotEmpty) {
          final distALinea = _distanciaMetros(
            _ubicacionActual!,
            _polylineTaxiPuntos.first,
          );

          // 2️⃣ Desvío fuerte (> 40 m): recalcular ruta de taxi
          if (distALinea > 40) {
            await _recalcularRutaTaxiDesdePosicionActual(apiKey);
          } else {
            _actualizarPolylineTrayectoTaxiConProgreso();
          }
        }

        // 3️⃣ Llegada automática (≤ 10 m al destino)
        if (distMetros <= 10) {
          debugPrint("✅ Has llegado al destino del taxi.");
          await detenerSeguimientoTrayectoTaxi(porLlegadaAuto: true);
        }

        notifyListeners();
      },
    );
  }

  /// ⏹ Detener seguimiento del trayecto del taxi (CU-7)
  Future<void> detenerSeguimientoTrayectoTaxi({
    bool porLlegadaAuto = false,
  }) async {
    _timerSeguimientoTrayectoTaxi?.cancel();
    _timerSeguimientoTrayectoTaxi = null;

    _seguimientoTrayectoTaxiActivo = false;

    if (porLlegadaAuto) {
      _llegoAutomaticamenteDestinoTaxi = true;
    }

    notifyListeners();
  }

  void mostrarPopupRutaCaminandoTaxi() {
    mostrarPopupTaxiCaminando = true;
    notifyListeners();
  }

  void ocultarPopupTaxiCaminando() {
    mostrarPopupTaxiCaminando = false;
    notifyListeners();
  }

  /// ❌ Limpia solo la ruta caminando al sitio (no todo el mapa)
  void limpiarRutaCaminandoTaxi() {
    _polylineCaminando.clear();
    _polylineCaminandoPuntos.clear();
    tiempoCaminando = null;
    distanciaCaminando = null;

    _timerSeguimientoTaxi?.cancel();
    _timerSeguimientoTaxi = null;
    _seguimientoTaxiActivo = false;
    _llegoAutomaticamenteTaxi = false;

    notifyListeners();
  }

  /// Marca que ya se mostró el diálogo de llegada al sitio (CU-9)
  void marcarDialogoLlegadaTaxiMostrado() {
    if (!_llegoAutomaticamenteTaxi) return;
    _llegoAutomaticamenteTaxi = false;
    notifyListeners();
  }

  /// Marca que ya se mostró el diálogo de llegada al destino en taxi (CU-7)
  void marcarDialogoLlegadaDestinoTaxiMostrado() {
    if (!_llegoAutomaticamenteDestinoTaxi) return;
    _llegoAutomaticamenteDestinoTaxi = false;
    notifyListeners();
  }
}