import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:vamonos_recio/modelos/RutaModel.dart';
import 'package:vamonos_recio/services/LocationService.dart';
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
    _paradaObjetivo = null;
    _paradaObjetivo = null;
    limpiarSeguimientoRuta();
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

    double _distanciaMetros(LatLng a, LatLng b) {
    const R = 6371000; // metros
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);

    final aHarv = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1) * cos(lat2) * (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(aHarv), sqrt(1 - aHarv));
    return R * c;
  }

  String _formatearDistancia(double metros) {
    if (metros < 1000) {
      return "${metros.toStringAsFixed(0)} m";
    } else {
      return "${(metros / 1000).toStringAsFixed(1)} km";
    }
  }

  String _formatearTiempo(double segundos) {
    final minutos = segundos / 60;
    if (minutos < 1) {
      return "${segundos.toStringAsFixed(0)} s";
    } else if (minutos < 60) {
      return "${minutos.toStringAsFixed(0)} min";
    } else {
      final horas = minutos / 60;
      final minsRestantes = (minutos % 60).round();
      return "${horas.floor()} h ${minsRestantes} min";
    }
  }

  Future<bool> _asegurarPermisoUbicacion() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      debugPrint("⚠️ GPS desactivado");
      return false;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        debugPrint("⚠️ Permiso de ubicación denegado");
        return false;
      }
    }
    if (permiso == LocationPermission.deniedForever) {
      debugPrint("⚠️ Permiso de ubicación bloqueado permanentemente");
      return false;
    }
    return true;
  }

  /// 🔁 Limpia todo del mapa
  void limpiarMapa() {
    _polylines.clear();
    _marcadores.clear();
    _rutasCandidatas.clear();
    _destinoSeleccionado = null;
    _paradaObjetivo = null;
    _paradaObjetivo = null;
    limpiarSeguimientoRuta();
    notifyListeners();
  }

    // --------------------------------------------------
  // 5️⃣ Calcular ruta a pie (CU-4 - Parada más cercana)
  // --------------------------------------------------
  LatLng? _ubicacionActual;
  ParadaModel? _paradaMasCercana;
  Set<Polyline> _rutaCaminando = {};
  List<LatLng> _rutaCaminandoPuntos = []; // puntos completos de la polyline
  Set<Marker> _markers = {};
  bool _mostrandoRutaCaminando = false;
  String? _distanciaCaminando;
  String? _tiempoCaminando;
  bool _mostrarPopupCaminando = false;
  ParadaModel? _paradaObjetivo;
  ParadaModel? get paradaObjetivo => _paradaObjetivo;
  bool get mostrarPopupCaminando => _mostrarPopupCaminando;
  LatLng? get ubicacionActual => _ubicacionActual;
  ParadaModel? get paradaMasCercana => _paradaMasCercana;
  Set<Polyline> get rutaCaminando => _rutaCaminando;
  bool get mostrandoRutaCaminando => _mostrandoRutaCaminando;
  String? get distanciaCaminando => _distanciaCaminando;
  String? get tiempoCaminando => _tiempoCaminando;

  // CU-6: Seguimiento de trayecto de ruta (dentro del camión)
  Timer? _timerSeguimientoRuta;
  bool _seguimientoRutaActivo = false;
  bool get seguimientoRutaActivo => _seguimientoRutaActivo;
  String? _distanciaRestanteRuta;
  String? _tiempoRestanteRuta;
  String? get distanciaRestanteRuta => _distanciaRestanteRuta;
  String? get tiempoRestanteRuta => _tiempoRestanteRuta;
  bool _avisoProximoParada = false; // para aviso anticipado
  bool get avisoProximoParada => _avisoProximoParada;
  bool _llegoAutomaticamenteRuta = false; // para diálogo "has llegado en la ruta"
  bool get llegoAutomaticamenteRuta => _llegoAutomaticamenteRuta;


  // --- Seguimiento en vivo CU-8 ---
  Timer? _timerSeguimiento;
  bool _seguimientoActivo = false;
  bool get seguimientoActivo => _seguimientoActivo;
  bool _llegoAutomaticamente = false; // Para disparar el diálogo "Has llegado a la parada"
  bool get llegoAutomaticamente => _llegoAutomaticamente;
  final LocationService _locationService = LocationService();


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

  /// 🔵 CU-6: Calcula la parada más cercana AL DESTINO pero SOLO entre paradas de la ruta seleccionada
  Future<void> calcularParadaObjetivo({
    required int idRuta,
    required LatLng destino,
  }) async {
    try {
      final paradas = await _db.obtenerParadasPorRuta(idRuta);
      if (paradas.isEmpty) return;

      ParadaModel? masCercana;
      double minDist = double.infinity;

      for (var p in paradas) {
        final dist = _distanciaMetros(
          LatLng(p.latitud, p.longitud),
          destino,
        );

        if (dist < minDist) {
          minDist = dist;
          masCercana = p;
        }
      }

      _paradaObjetivo = masCercana;

      // 👉 Añadir marcador visual en el mapa
      if (_paradaObjetivo != null) {
        _marcadores.removeWhere((m) => m.markerId.value == "parada_objetivo");

        _marcadores.add(
          Marker(
            markerId: const MarkerId("parada_objetivo"),
            position: LatLng(
              _paradaObjetivo!.latitud,
              _paradaObjetivo!.longitud,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: _paradaObjetivo!.nombre,
              snippet: "Parada para bajar",
            ),
          ),
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint("❌ Error al calcular parada objetivo CU-6: $e");
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

        // 👉 Guardamos todos los puntos para poder "consumir" la ruta
        _rutaCaminandoPuntos = polylineCoords;

        _rutaCaminando.clear();
        _rutaCaminando.add(
          Polyline(
            polylineId: const PolylineId("rutaCaminando"),
            color: const Color.fromARGB(255, 65, 105, 225), // Azul caminata
            width: 5,
            points: polylineCoords,
            patterns: [PatternItem.dot, PatternItem.gap(20)], // línea punteada
            geodesic: true,
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

    /// 🔄 Actualiza la polyline para que solo se muestre el tramo restante
  void _actualizarPolylineConProgreso() {
    if (_ubicacionActual == null || _rutaCaminandoPuntos.isEmpty) return;

    int indexMasCercano = 0;
    double minDist = double.infinity;

    for (int i = 0; i < _rutaCaminandoPuntos.length; i++) {
      final d = _distanciaMetros(_ubicacionActual!, _rutaCaminandoPuntos[i]);
      if (d < minDist) {
        minDist = d;
        indexMasCercano = i;
      }
    }

    final restantes = _rutaCaminandoPuntos.sublist(indexMasCercano);

    _rutaCaminando.clear();

    if (restantes.length > 1) {
      _rutaCaminando.add(
        Polyline(
          polylineId: const PolylineId("rutaCaminando"),
          color: const Color.fromARGB(255, 65, 105, 225),
          width: 5,
          points: restantes,
          patterns: [PatternItem.dot, PatternItem.gap(20)],
          geodesic: true,
        ),
      );
    }
  }

    /// ▶️ Iniciar seguimiento a pie hacia la parada más cercana (CU-8)
  Future<void> iniciarSeguimientoAPieParada({required String apiKey}) async {
    if (_paradaMasCercana == null) {
      debugPrint("⚠️ No hay parada más cercana definida para seguimiento.");
      return;
    }

    _seguimientoActivo = true;
    _llegoAutomaticamente = false;
    notifyListeners();

    // Obtener ubicación inicial
    final posInicial = await _locationService.getCurrentLocation();
    if (posInicial != null) {
      _ubicacionActual = LatLng(posInicial.latitude, posInicial.longitude);
    }

    final destinoParada = LatLng(
      _paradaMasCercana!.latitud,
      _paradaMasCercana!.longitud,
    );

    // Cancelar timer anterior si existía
    _timerSeguimiento?.cancel();

    // Timer cada 2 segundos (suficiente para seguimiento sin mareo)
    _timerSeguimiento = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!_seguimientoActivo) return;

        final pos = await _locationService.getCurrentLocation();
        if (!_seguimientoActivo) return;
        if (pos == null) return;

        _ubicacionActual = LatLng(pos.latitude, pos.longitude);

        // Distancia directa a la parada
        final distMetros =
            _distanciaMetros(_ubicacionActual!, destinoParada);
        _distanciaCaminando = "${distMetros.toStringAsFixed(0)} m";

        // Tiempo estimado con ~1.4 m/s
        const velocidadMedia = 1.4;
        final segundos = distMetros / velocidadMedia;
        final minutos = (segundos / 60).round();
        _tiempoCaminando = "$minutos min";

        // 1️⃣ Consumir polyline si vamos sobre la ruta
        if (_rutaCaminandoPuntos.isNotEmpty) {
          final distALinea = _distanciaMetros(
            _ubicacionActual!,
            _rutaCaminandoPuntos.first,
          );

          // 2️⃣ Si se desvía mucho de la ruta (> 30 m), recalcular trayecto
          if (distALinea > 30) {
            await _recalcularRutaCaminandoDesdePosicionActual(
              apiKey,
              destinoParada,
            );
          } else {
            _actualizarPolylineConProgreso();
          }
        }

        // 3️⃣ Llegada automática (<= 5 m)
        if (distMetros <= 5) {
          debugPrint("✅ Llegaste a la parada más cercana.");
          await detenerSeguimientoAPie(porLlegadaAuto: true);
        }

        notifyListeners();
      },
    );
  }

  /// ▶️ CU-6: Iniciar seguimiento de trayecto de ruta (dentro del camión)
  Future<void> iniciarSeguimientoRuta() async {
    if (_paradaObjetivo == null) {
      debugPrint("⚠️ CU-6: No hay parada objetivo definida para seguimiento.");
      return;
    }

    // Pedir permisos de ubicación (reuso lo que ya tienes si quieres)
    final tienePermiso = await _asegurarPermisoUbicacion();
    if (!tienePermiso) return;

    _seguimientoRutaActivo = true;
    _llegoAutomaticamenteRuta = false;
    // Reiniciamos aviso anticipado
    _avisoProximoParada = false;
    notifyListeners();

    // Ubicación inicial
    final posInicial = await _locationService.getCurrentLocation();
    if (posInicial != null) {
      _ubicacionActual = LatLng(posInicial.latitude, posInicial.longitude);
    }

    final destinoParada = LatLng(
      _paradaObjetivo!.latitud,
      _paradaObjetivo!.longitud,
    );

    // Cancelar cualquier timer previo
    _timerSeguimientoRuta?.cancel();

    // Timer cada 3 segundos (suficiente para ir en camión sin mareo)
    _timerSeguimientoRuta = Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        if (!_seguimientoRutaActivo) return;

        final pos = await _locationService.getCurrentLocation();
        if (!_seguimientoRutaActivo) return;
        if (pos == null) return;

        _ubicacionActual = LatLng(pos.latitude, pos.longitude);

        // Distancia directa a la parada objetivo
        final distMetros =
          _distanciaMetros(_ubicacionActual!, destinoParada);
        _distanciaRestanteRuta = _formatearDistancia(distMetros);

        // Tiempo estimado con velocidad de camión (~ 9 m/s ≈ 32 km/h)
        const velocidadBus = 9.0; // m/s
        final segundos = distMetros / velocidadBus;
        _tiempoRestanteRuta = _formatearTiempo(segundos);

        // 1️⃣ Aviso anticipado cuando esté cerca (ej. 200 m)
        if (!_avisoProximoParada && distMetros <= 200 && distMetros > 5) {
          _avisoProximoParada = true; // La vista reaccionará y luego lo apagamos
        }

        // 2️⃣ Llegada automática (<= 5 m)
        if (distMetros <= 5) {
          debugPrint("✅ CU-6: Llegaste a la parada objetivo de la ruta.");
          await detenerSeguimientoRuta(porLlegadaAuto: true);
        }

        notifyListeners();
      },
    );
  }

    /// 🔁 Recalcula la ruta caminando desde la posición actual hasta la parada
  Future<void> _recalcularRutaCaminandoDesdePosicionActual(
    String apiKey,
    LatLng destinoParada,
  ) async {
    if (_ubicacionActual == null) return;

    await calcularRutaCaminando(
      origen: _ubicacionActual!,
      destino: destinoParada,
      apiKey: apiKey,
    );
  }

  /// ⏹ CU-6: Detener seguimiento de trayecto de ruta
  Future<void> detenerSeguimientoRuta({bool porLlegadaAuto = false}) async {
    _timerSeguimientoRuta?.cancel();
    _timerSeguimientoRuta = null;

    _seguimientoRutaActivo = false;

    if (porLlegadaAuto) {
      _llegoAutomaticamenteRuta = true;
    }

    notifyListeners();
  }

    /// ⏹ Detener seguimiento a pie (CU-8)
  Future<void> detenerSeguimientoAPie({bool porLlegadaAuto = false}) async {
    _timerSeguimiento?.cancel();
    _timerSeguimiento = null;

    _seguimientoActivo = false;

    if (porLlegadaAuto) {
      // Esto hará que la vista muestre el diálogo "Has llegado a la parada"
      _llegoAutomaticamente = true;
    }

    notifyListeners();
  }

    /// ❌ Limpia la ruta caminando y detiene seguimiento
  void limpiarRutaCaminando() {
    _rutaCaminando.clear();
    _rutaCaminandoPuntos.clear();
    _mostrandoRutaCaminando = false;
    _paradaMasCercana = null;

    _timerSeguimiento?.cancel();
    _timerSeguimiento = null;
    _seguimientoActivo = false;

    _distanciaCaminando = null;
    _tiempoCaminando = null;
    _llegoAutomaticamente = false;

    // Quitamos marcador de parada más cercana
    _marcadores
        .removeWhere((m) => m.markerId.value == "parada_mas_cercana");

    notifyListeners();
  }

  /// ❌ Limpia solo el estado del seguimiento de ruta (CU-6)
  void limpiarSeguimientoRuta() {
    _timerSeguimientoRuta?.cancel();
    _timerSeguimientoRuta = null;

    _seguimientoRutaActivo = false;
    _distanciaRestanteRuta = null;
    _tiempoRestanteRuta = null;
    _avisoProximoParada = false;
    _llegoAutomaticamenteRuta = false;

    notifyListeners();
  }

  /// Marca que ya se mostró el diálogo de llegada CU-6
  void marcarDialogoLlegadaRutaMostrado() {
    if (!_llegoAutomaticamenteRuta) return;
    _llegoAutomaticamenteRuta = false;
    notifyListeners();
  }

  /// Marca que ya se mostró el aviso de "ya casi llegas"
  void marcarAvisoProximoParadaMostrado() {
    if (!_avisoProximoParada) return;
    _avisoProximoParada = false;
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

    /// Marca que ya se mostró el diálogo de llegada
  void marcarDialogoLlegadaMostrado() {
    if (!_llegoAutomaticamente) return;
    _llegoAutomaticamente = false;
    notifyListeners();
  }

    /// 📌 PRUEBA UNITARIA SIMULADA CU-6
  ///
  /// Simula el seguimiento dentro del camión con varias distancias:
  ///  - Lejos (sin aviso)
  ///  - Cerca (activa avisoProximoParada)
  ///  - Muy cerca (dispara llegada automática y detiene seguimiento)
  ///
  /// Imprime en consola el estado en cada paso.
  Future<void> pruebaUnitariaCu6Simulada() async {
    // Distancias simuladas en metros:
    //  1) 500 m -> lejos
    //  2) 150 m -> debe activar avisoProximoParada
    //  3) 4 m   -> debe marcar llegada automática y detener seguimiento
    final distanciasSimuladas = [500.0, 150.0, 4.0];

    // Preparamos el estado como si ya se hubiera definido una parada objetivo
    _seguimientoRutaActivo = true;
    _llegoAutomaticamenteRuta = false;
    _avisoProximoParada = false;
    _distanciaRestanteRuta = null;
    _tiempoRestanteRuta = null;

    debugPrint("===== INICIO PRUEBA UNITARIA CU-6 =====");

    for (final distMetros in distanciasSimuladas) {
      if (!_seguimientoRutaActivo) {
        debugPrint(
            "Seguimiento ya está detenido, se detiene la simulación aquí.");
        break;
      }

      // Usamos la misma lógica de producción
      _distanciaRestanteRuta = _formatearDistancia(distMetros);

      const velocidadBus = 9.0; // m/s como en tu código
      final segundos = distMetros / velocidadBus;
      _tiempoRestanteRuta = _formatearTiempo(segundos);

      // 1️⃣ Aviso anticipado cuando esté cerca (ej. 200 m > dist > 5)
      if (!_avisoProximoParada && distMetros <= 200 && distMetros > 5) {
        _avisoProximoParada = true;
        debugPrint(
          "AVISO: Te estás acercando a la parada. "
          "(dist = ${distMetros.toStringAsFixed(1)} m)",
        );
      }

      // 2️⃣ Llegada automática (<= 5 m)
      if (distMetros <= 5) {
        debugPrint(
          "LLEGADA AUTOMÁTICA: Estás en la parada. "
          "(dist = ${distMetros.toStringAsFixed(1)} m)",
        );
        await detenerSeguimientoRuta(porLlegadaAuto: true);
      }

      // Imprimimos el estado actual
      debugPrint(
        "Estado simulación -> "
        "distanciaRestanteRuta=$_distanciaRestanteRuta, "
        "tiempoRestanteRuta=$_tiempoRestanteRuta, "
        "avisoProximoParada=$_avisoProximoParada, "
        "llegoAutomaticamenteRuta=$_llegoAutomaticamenteRuta, "
        "seguimientoRutaActivo=$_seguimientoRutaActivo",
      );

      // Pausa pequeña solo para que en consola se vea separado (en test ni se nota)
      await Future.delayed(const Duration(milliseconds: 10));
    }

    debugPrint("===== FIN PRUEBA UNITARIA CU-6 =====");
  }

    /// 📌 PRUEBA UNITARIA SIMULADA CU-8
  ///
  /// Simula el seguimiento a pie hacia la parada más cercana con varias
  /// distancias:
  ///  - Lejos (solo actualiza distancia/tiempo).
  ///  - Distancia intermedia donde se simula un "desvío" y recalculo.
  ///  - Muy cerca (dispara llegada automática y detiene seguimiento).
  ///
  /// Solo imprime en consola, no usa GPS ni Google Maps reales.
  Future<void> pruebaUnitariaCu8Simulada() async {
    // Distancias simuladas en metros:
    //  1) 300 m -> lejos
    //  2) 80 m  -> punto donde simulamos desvío y "recalculo"
    //  3) 3 m   -> llegada automática
    final distanciasSimuladas = [300.0, 80.0, 3.0];

    // Preparamos el estado como si ya se hubiera iniciado el seguimiento
    _seguimientoActivo = true;
    _llegoAutomaticamente = false;
    _distanciaCaminando = null;
    _tiempoCaminando = null;

    debugPrint("===== INICIO PRUEBA UNITARIA CU-8 =====");

    for (final distMetros in distanciasSimuladas) {
      if (!_seguimientoActivo) {
        debugPrint(
          "Seguimiento ya está detenido, se detiene la simulación aquí.",
        );
        break;
      }

      // ✅ Usamos la misma lógica que en producción para calcular tiempo
      _distanciaCaminando = "${distMetros.toStringAsFixed(0)} m";

      const velocidadMedia = 1.4; // m/s (~5 km/h)
      final segundos = distMetros / velocidadMedia;
      final minutos = (segundos / 60).round();
      _tiempoCaminando = "$minutos min";

      // 1️⃣ Simular un "desvío" y un posible recalculo de ruta
      if (distMetros <= 100 && distMetros > 20) {
        debugPrint(
          "DESVÍO SIMULADO: el trabajador se alejó de la ruta a pie, "
          "se debería recalcular el trayecto. "
          "(dist = ${distMetros.toStringAsFixed(1)} m)",
        );
      }

      // 2️⃣ Llegada automática (<= 5 m) como en el código real
      if (distMetros <= 5) {
        debugPrint(
          "LLEGADA AUTOMÁTICA: Has llegado a la parada más cercana. "
          "(dist = ${distMetros.toStringAsFixed(1)} m)",
        );
        await detenerSeguimientoAPie(porLlegadaAuto: true);
      }

      // Imprimimos el estado actual
      debugPrint(
        "Estado simulación CU-8 -> "
        "distanciaCaminando=$_distanciaCaminando, "
        "tiempoCaminando=$_tiempoCaminando, "
        "llegoAutomaticamente=$_llegoAutomaticamente, "
        "seguimientoActivo=$_seguimientoActivo",
      );

      // Pequeña pausa solo para separar logs
      await Future.delayed(const Duration(milliseconds: 10));
    }

    debugPrint("===== FIN PRUEBA UNITARIA CU-8 =====");
  }
}