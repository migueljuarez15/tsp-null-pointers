import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/DatabaseHelper.dart';
import '../services/LocationService.dart';
import '../modelos/ParadaModel.dart';
import '../modelos/SitioModel.dart';
import '../services/MapService.dart';

// ⭐ NUEVO: para poder interactuar con otros ViewModels sin usar BuildContext
import 'RecorridoViewModel.dart';
import 'SitioViewModel.dart';

class HomeViewModel extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _locationService = LocationService();

  bool mostrarParadas = true;
  Set<Marker> marcadores = {};
  Set<Polyline> polylines = {};
  LatLng? ubicacionActual;
  LatLng? destinoSeleccionado;
  bool cargando = true;

  // ⭐ NUEVO: estado que antes vivía en HomeView
  bool switchModo = false;                // Modo Transporte (false) / Taxi (true)
  bool mostrandoMensaje = true;          // Mensaje "Modo Taxi / Modo Transporte"
  double zoomActual = 13;                // Zoom actual del mapa
  String textoBusqueda = "Buscar";       // Texto de la barra de búsqueda
  String? rutaSeleccionadaId;            // Ruta seleccionada en el dropdown
  Set<Circle> circulos = {};             // Círculos de paradas / sitios
  bool ocultarParadas = false; // cuando es true, no se dibujan paradas (circles)
  bool ocultarSitios = false;  // cuando es true, no se dibujan sitios de taxi

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

  // ⭐ NUEVO: inicializar la pantalla Home (ubicación + contenido + mensaje de modo)
  Future<void> inicializarHome() async {
    await inicializarMapa();      // reutilizamos lo que ya tenías
    await cargarContenido();      // carga paradas o sitios según el modo

    mostrandoMensaje = true;
    notifyListeners();

    Future.delayed(const Duration(seconds: 3), () {
      mostrandoMensaje = false;
      notifyListeners();
    });
  }

  // ⭐ NUEVO: se llama cuando se mueve la cámara (para recalcular qué mostrar)
  Future<void> onCameraMove(double nuevoZoom) async {
    zoomActual = nuevoZoom;
    await cargarContenido();
  }

  // ⭐ NUEVO: cargar contenido según el modo actual
  Future<void> cargarContenido() async {
    if (switchModo) {
      await _cargarSitiosOptimizado();
    } else {
      await _cargarParadasOptimizado();
    }
  }

  // ⭐ NUEVO: cargar paradas de forma optimizada según zoom
  Future<void> _cargarParadasOptimizado() async {
    final todasParadas = await _db.obtenerParadas();

    Set<Circle> visibles = {};
    int step;

    if (zoomActual < 11) {
      step = 25;
    } else if (zoomActual < 13) {
      step = 10;
    } else if (zoomActual < 15) {
      step = 5;
    } else {
      step = 1;
    }

    for (int i = 0; i < todasParadas.length; i += step) {
      final p = todasParadas[i];
      visibles.add(
        Circle(
          circleId: CircleId('parada_${p.idParada}'),
          center: LatLng(p.latitud, p.longitud),
          radius: 15,
          fillColor: const Color(0xFF137fec).withOpacity(0.5),
          strokeColor: Colors.blueAccent,
          strokeWidth: 1,
          // ❗ Aquí ya no usamos ScaffoldMessenger, eso se manejará en la vista
        ),
      );
    }

    circulos = visibles;
    notifyListeners();
  }

  // ⭐ NUEVO: cargar sitios de taxi de forma optimizada según zoom
  Future<void> _cargarSitiosOptimizado() async {
    final todosSitios = await _db.obtenerSitios();

    Set<Circle> visibles = {};
    int step;

    if (zoomActual < 11) {
      step = 25;
    } else if (zoomActual < 13) {
      step = 10;
    } else if (zoomActual < 15) {
      step = 5;
    } else {
      step = 1;
    }

    for (int i = 0; i < todosSitios.length; i += step) {
      final s = todosSitios[i];
      visibles.add(
        Circle(
          circleId: CircleId('sitio_${s.idSitio}'),
          center: LatLng(s.latitud, s.longitud),
          radius: 15,
          fillColor:
              const Color.fromARGB(255, 236, 76, 76).withOpacity(0.5),
          strokeColor: const Color.fromARGB(255, 255, 44, 44),
          strokeWidth: 1,
        ),
      );
    }

    circulos = visibles;
    notifyListeners();
  }

  // ⭐ NUEVO: cambiar entre modo transporte público y taxi
  Future<void> toggleModo({
    required RecorridoViewModel recorridoVM,
    required SitioViewModel sitioVM,
  }) async {
    // Limpiar estado en otros ViewModels
    recorridoVM.resetearTodo();
    recorridoVM.limpiarRutaCaminando();
    recorridoVM.ocultarPopupRutaCaminando();
    sitioVM.limpiarMapaTaxi();
    ocultarParadas = false;
    ocultarSitios = false;

    // Limpiar estado local
    rutaSeleccionadaId = null;
    textoBusqueda = "Buscar";
    destinoSeleccionado = null;
    circulos.clear();

    // Cambiar modo
    switchModo = !switchModo;

    // Mostrar mensaje de modo
    mostrandoMensaje = true;
    notifyListeners();

    // Recargar contenido según el modo
    await cargarContenido();

    // Ocultar mensaje después de 3s
    Future.delayed(const Duration(seconds: 3), () {
      mostrandoMensaje = false;
      notifyListeners();
    });
  }

  // ⭐ NUEVO: marcar destino (fusiona lógica de CU-1 y CU-2 que tenías en HomeView)
  Future<void> marcarDestino(
    LatLng destino, {
    required RecorridoViewModel recorridoVM,
    required SitioViewModel sitioVM,
    required String apiKey,
  }) async {
    // Asegurarnos de tener ubicación actual
    if (ubicacionActual == null) {
      final loc = await _locationService.getCurrentLocation();
      if (loc != null) {
        ubicacionActual = LatLng(loc.latitude, loc.longitude);
      }
    }

    if (ubicacionActual == null) {
      debugPrint("No se pudo obtener la ubicación actual");
      return;
    }

    if (switchModo) {
      // 🚕 Modo Taxi
      await sitioVM.cargarSitios();
      final sitio = await sitioVM.obtenerSitioMasCercano(ubicacionActual!);

      if (sitio != null) {
        // 🚶 Primero: ruta caminando al sitio
        await sitioVM.calcularRutaCaminandoAlSitio(
          origen: ubicacionActual!,
          apiKey: apiKey,
        );

        // 🚕 Luego: ruta taxi desde el sitio al destino
        await sitioVM.calcularRutaTaxi(
          origen: LatLng(sitio.latitud, sitio.longitud),
          destino: destino,
          apiKey: apiKey,
        );
      }
    } else {
      // 🚌 Modo Transporte público
      recorridoVM.marcarDestino(destino);
      await recorridoVM.buscarRutasCercanas(destino);
    }

    destinoSeleccionado = destino;
    textoBusqueda = "Destino seleccionado";
    notifyListeners();
  }

  // ⭐ NUEVO: limpiar selección cuando cierras el dropdown de rutas
  void limpiarSeleccionRutas(RecorridoViewModel recorridoVM) {
    recorridoVM.resetearTodo();
    recorridoVM.limpiarRutaCaminando();
    recorridoVM.ocultarPopupRutaCaminando();
    ocultarParadas = false;

    rutaSeleccionadaId = null;
    textoBusqueda = "Buscar";
    destinoSeleccionado = null;
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
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange),
      ),
      const Marker(
        markerId: MarkerId("destino"),
        position: LatLng(0, 0), // ⚠️ OJO: aquí tú ya usas "destino" en tu implementación real
        infoWindow: InfoWindow(title: "🎯 Destino"),
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

  void setOcultarParadas(bool valor) {
    if (ocultarParadas == valor) return;
    ocultarParadas = valor;
    notifyListeners();
  }

  void setOcultarSitios(bool valor) {
    if (ocultarSitios == valor) return;
    ocultarSitios = valor;
    notifyListeners();
  }
}
