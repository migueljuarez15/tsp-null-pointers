import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:vamonos_recio/modelos/ParadaModel.dart';
import 'package:vamonos_recio/modelos/SitioModel.dart';
import 'package:vamonos_recio/vistamodelos/HomeViewModel.dart';
import 'package:vamonos_recio/vistamodelos/RecorridoViewModel.dart';
import '../services/DatabaseHelper.dart';
import '../services/MapService.dart';
import 'BusquedaView.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

String _textoBusqueda = "Buscar";

class _HomeViewState extends State<HomeView> {
  GoogleMapController? mapController;
  bool switchModo = false;
  bool mostrandoMensaje = true;
  double _zoomActual = 13;
  LatLng? _ubicacionActual;
  LatLng? _destinoSeleccionado;
  Polyline? _polylineRutaSimulada;

  List<ParadaModel> _todasParadas = [];
  List<SitioModel> _todosSitios = [];

  Set<Polyline> _rutas = {};
  Set<Circle> _circulos = {};
  Set<Marker> _markers = {}; // 👈 Añadido: para el destino buscado

  final _db = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _cargarContenido();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  /// 🔹 Carga contenido según modo actual
  Future<void> _cargarContenido() async {
    if (switchModo) {
      await _mostrarSitioMasCercano();
    } else {
      await _cargarParadasOptimizado();
    }
  }

  /// 🚌 Carga paradas reales desde BD y filtra según zoom
  Future<void> _cargarParadasOptimizado() async {
    final db = DatabaseHelper();
    _todasParadas = await db.obtenerParadas();

    Set<Circle> visibles = {};

    int step;
    if (_zoomActual < 11) {
      step = 25;
    } else if (_zoomActual < 13) {
      step = 10;
    } else if (_zoomActual < 15) {
      step = 5;
    } else {
      step = 1;
    }

    for (int i = 0; i < _todasParadas.length; i += step) {
      final p = _todasParadas[i];
      visibles.add(
        Circle(
          circleId: CircleId('parada_${p.idParada}'),
          center: LatLng(p.latitud, p.longitud),
          radius: 15,
          fillColor: const Color(0xFF137fec).withOpacity(0.5),
          strokeColor: Colors.blueAccent,
          strokeWidth: 1,
          consumeTapEvents: true,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(p.nombre)),
            );
          },
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  /// 🚕 Carga sitios reales desde BD y filtra según zoom
  Future<void> _cargarSitiosOptimizado() async {
    final db = DatabaseHelper();
    _todosSitios = await db.obtenerSitios();

    Set<Circle> visibles = {};

    int step;
    if (_zoomActual < 11) {
      step = 25;
    } else if (_zoomActual < 13) {
      step = 10;
    } else if (_zoomActual < 15) {
      step = 5;
    } else {
      step = 1;
    }

    for (int i = 0; i < _todosSitios.length; i += step) {
      final s = _todosSitios[i];
      visibles.add(
        Circle(
          circleId: CircleId('sitio_${s.idSitio}'),
          center: LatLng(s.latitud, s.longitud),
          radius: 15,
          fillColor: const Color.fromARGB(255, 236, 76, 76).withOpacity(0.5),
          strokeColor: const Color.fromARGB(255, 255, 44, 44),
          strokeWidth: 1,
          consumeTapEvents: true,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.nombre)),
            );
          },
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  /// 🔁 Alterna entre modo camión y paradas
  Future<void> _toggleModo() async {
    setState(() {
      switchModo = !switchModo;
      mostrandoMensaje = true;
    });
    await _cargarContenido();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  /// 📍 Agrega marcador del destino buscado
Future<void> _marcarDestino(LatLng destino) async {
  _ubicacionActual ??= const LatLng(22.7700, -102.5720);

  setState(() {
    _destinoSeleccionado = destino;

    // 🔹 Limpiamos solo rutas, no los marcadores todavía
    _rutas.clear();

    // 🔹 Agregamos el marcador del destino (rojo)
    _markers.removeWhere((m) => m.markerId.value == "destino_buscado");
    _markers.add(
      Marker(
        markerId: const MarkerId("destino_buscado"),
        position: destino,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Destino seleccionado"),
      ),
    );
  });

  if (switchModo) {
    // 🚕 Si estamos en modo taxis, también mostrar el sitio más cercano
    await _mostrarSitioMasCercano(agregarMarcador: true);
  } else {
    // 🚌 Si es modo camión, dibujar la ruta simulada
    _dibujarRutaSimulada(_ubicacionActual!, destino);
  }
}

/// 🚖 Muestra el sitio más cercano (opcionalmente agregando marcador)
Future<void> _mostrarSitioMasCercano({bool agregarMarcador = false}) async {
  final viewModel = context.read<HomeViewModel>();

  await viewModel.inicializarMapa();
  final sitio = await viewModel.obtenerSitioMasCercano();

  if (sitio != null && viewModel.ubicacionActual != null) {
    if (agregarMarcador) {
      // 👇 NO limpiar los marcadores, solo actualizar o añadir el del sitio
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == "sitio_cercano");
        _markers.add(
          Marker(
            markerId: const MarkerId('sitio_cercano'),
            position: LatLng(sitio.latitud, sitio.longitud),
            infoWindow: InfoWindow(
              title: sitio.nombre,
              snippet: 'Sitio más cercano',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
      });
    } else {
      // Versión original si se llama desde el cambio de modo
      setState(() {
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId('sitio_cercano'),
            position: LatLng(sitio.latitud, sitio.longitud),
            infoWindow: InfoWindow(
              title: sitio.nombre,
              snippet: 'Sitio más cercano',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
      });
    }

    // 🔹 Centra el mapa entre el destino y el sitio más cercano si ambos existen
    if (_destinoSeleccionado != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          min(_destinoSeleccionado!.latitude, sitio.latitud),
          min(_destinoSeleccionado!.longitude, sitio.longitud),
        ),
        northeast: LatLng(
          max(_destinoSeleccionado!.latitude, sitio.latitud),
          max(_destinoSeleccionado!.longitude, sitio.longitud),
        ),
      );
      mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
    } else {
      // Si no hay destino, centramos solo en el sitio
      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(sitio.latitud, sitio.longitud),
          15,
        ),
      );
    }
  }
}

  void _dibujarRutaSimulada(LatLng inicio, LatLng destino) {
    // 🔸 Simulamos una "ruta" con puntos intermedios
    final List<LatLng> puntos = [
      inicio,
      LatLng(
        (inicio.latitude + destino.latitude) / 2 + 0.002, 
        (inicio.longitude + destino.longitude) / 2 - 0.002,
      ),
      destino,
    ];

    setState(() {
      _rutas.clear();
      _rutas.add(
        Polyline(
          polylineId: const PolylineId("ruta_simulada"),
          points: puntos,
          color: Colors.blueAccent,
          width: 5,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<HomeViewModel>(context);
    final recorridoVM = context.read<RecorridoViewModel>();
    final primary = const Color(0xFF137fec);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: MapService.centroZacatecas,
                zoom: 13,
              ),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (position) async {
                _zoomActual = position.zoom;
                if (!switchModo) {
                  await _cargarParadasOptimizado();
                }
              },
              markers: _markers,
              //markers: recorridoVM.marcadores, los comente por que no son relevantes para los taxis
              //polylines: recorridoVM.polylines,
              circles: _circulos,
              //markers: _markers.union(viewModel.marcadores), // 👈 marcador del destino
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
            ),

            // 🔍 Barra de búsqueda clickeable
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: GestureDetector(
                onTap: () async {
                  final resultado = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BusquedaView()),
                  );

                  if (resultado != null && mapController != null) {
                    final LatLng destino = resultado['coordenadas'];
                    final String nombre = resultado['nombre'];

                    mapController!.animateCamera(
                      CameraUpdate.newLatLngZoom(destino, 15),
                    );

                    // ✅ AQUI se usa el método que faltaba
                    _marcarDestino(destino);

                    // 👇 Llama al ViewModel (solo si estás en modo camión)
                    if (!switchModo) {
                      await recorridoVM.dibujarRutaDesdeBD(1); // ← ID de la ruta seleccionada
                    }

                    // 🔹 Actualiza el texto de la barra de búsqueda
                    setState(() {
                      _textoBusqueda = nombre;
                    });
                  }
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _textoBusqueda,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis, // 🔹 recorta con “...”
                          maxLines: 1,                     // 🔹 evita salto de línea
                          softWrap: false,                 // 🔹 mantiene en una sola línea
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 🟦 Mensaje temporal de modo
            if (mostrandoMensaje)
              Positioned(
                top: 70,
                left: 40,
                right: 40,
                child: AnimatedOpacity(
                  opacity: mostrandoMensaje ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.black87.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        switchModo
                            ? "Mostrando Sitios de Taxi"
                            : "Mostrando Paradas de Rutas",
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 🔁 Botón toggle modo
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: primary,
                onPressed: _toggleModo,
                child: Icon(
                  switchModo ? Icons.directions_bus : Icons.local_taxi,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //Taxis
 

}