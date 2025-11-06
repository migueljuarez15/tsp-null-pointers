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
String? _rutaSeleccionadaId;

class _HomeViewState extends State<HomeView> {
  GoogleMapController? mapController;
  bool switchModo = false;
  bool mostrandoMensaje = true;
  double _zoomActual = 13;
  LatLng? _destinoSeleccionado;

  List<ParadaModel> _todasParadas = [];
  List<SitioModel> _todosSitios = [];
  Set<Circle> _circulos = {};

  final _db = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _cargarContenido();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  Future<void> _cargarContenido() async {
    if (switchModo) {
      await _cargarSitiosOptimizado();
    } else {
      await _cargarParadasOptimizado();
    }
  }

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
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

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
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  // 🔁 Cambio de modo (Ruta <-> Taxi)
  Future<void> _toggleModo() async {
    final recorridoVM = context.read<RecorridoViewModel>();

    // 🧹 Limpieza total del mapa y estado
    recorridoVM.resetearTodo();
    setState(() {
      _rutaSeleccionadaId = null;
      _textoBusqueda = "Buscar";
      _destinoSeleccionado = null;
      _circulos.clear();
      switchModo = !switchModo;
      mostrandoMensaje = true;
    });

    await _cargarContenido();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  // 📍 Marcar destino o gestionar búsqueda
  void _marcarDestino(LatLng destino) async {
    final recorridoVM = context.read<RecorridoViewModel>();
    setState(() => _destinoSeleccionado = destino);

    if (!switchModo) {
      // 🚌 Lógica de rutas
      recorridoVM.marcarDestino(destino);
      await recorridoVM.buscarRutasCercanas(destino);
    } else {
      // 🚕 Lógica modo taxi
      recorridoVM.resetearTodo();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Modo Taxi activo: mostrando sitios disponibles"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF137fec);
    final recorridoVM = context.watch<RecorridoViewModel>();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: MapService.centroZacatecas, zoom: 13),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (position) async {
                _zoomActual = position.zoom;
                if (!switchModo) {
                  await _cargarParadasOptimizado();
                } else {
                  await _cargarSitiosOptimizado();
                }
              },
              markers: switchModo ? {} : recorridoVM.marcadores,
              polylines: switchModo ? {} : recorridoVM.polylines,
              circles: _circulos,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
            ),

            // 🔍 Barra de búsqueda
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
                    final recorridoVM = context.read<RecorridoViewModel>();
                    recorridoVM.resetearTodo();

                    final LatLng destino = resultado['coordenadas'];
                    final String nombre = resultado['nombre'];

                    mapController!.animateCamera(
                      CameraUpdate.newLatLngZoom(destino, 15),
                    );

                    setState(() {
                      _textoBusqueda = nombre;
                      _rutaSeleccionadaId = null;
                      _destinoSeleccionado = destino;
                    });

                    // 🔹 Lógica dependiente del modo
                    _marcarDestino(destino);
                  }
                },
                child: _buildSearchBar(),
              ),
            ),

            // 🧭 Dropdown rutas (solo si NO es modo taxi)
            if (!switchModo &&
                _destinoSeleccionado != null &&
                recorridoVM.rutasCandidatas.isNotEmpty)
              Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: _buildDropdown(recorridoVM),
              ),

            // 🟦 Mensaje de modo actual
            if (mostrandoMensaje) _buildModoMensaje(),

            // 🔁 Botón para cambiar modo
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

            if (recorridoVM.cargando)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  // 🔍 Barra de búsqueda visual
  Widget _buildSearchBar() => Container(
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
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  // 🧭 Dropdown con rutas personalizadas
  Widget _buildDropdown(RecorridoViewModel recorridoVM) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: recorridoVM.rutasCandidatas.any((ruta) =>
                        ruta.idRuta.toString() == _rutaSeleccionadaId)
                    ? _rutaSeleccionadaId
                    : null,
                hint: const Text("Selecciona una ruta sugerida"),
                items: recorridoVM.rutasCandidatas.map((ruta) {
                  Color colorFondo;
                  switch (ruta.idRuta) {
                    case 1:
                      colorFondo = const Color.fromARGB(255, 133, 205, 238);
                      break;
                    case 2:
                      colorFondo = const Color.fromARGB(255, 8, 83, 0);
                      break;
                    case 3:
                      colorFondo = const Color.fromARGB(255, 114, 114, 114);
                      break;
                    case 4:
                      colorFondo = const Color.fromARGB(255, 54, 54, 248);
                      break;
                    case 8:
                      colorFondo = const Color.fromARGB(255, 223, 104, 0);
                      break;
                    case 14:
                      colorFondo = const Color.fromARGB(255, 219, 166, 32);
                      break;
                    case 15:
                      colorFondo = const Color.fromARGB(255, 129, 0, 129);
                      break;
                    case 16:
                      colorFondo = const Color.fromARGB(255, 214, 214, 34);
                      break;
                    case 17:
                      colorFondo = const Color.fromARGB(255, 48, 199, 53);
                      break;
                    case 21:
                      colorFondo = const Color.fromARGB(255, 255, 0, 0);
                      break;
                    default:
                      colorFondo = Colors.grey;
                  }

                  return DropdownMenuItem<String>(
                    value: ruta.idRuta.toString(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: colorFondo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            ruta.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const Icon(Icons.directions_bus,
                              size: 18, color: Colors.white),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (valor) async {
                  if (valor != null) {
                    setState(() => _rutaSeleccionadaId = valor);
                    await recorridoVM.dibujarRutaDesdeBD(int.parse(valor));
                  }
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            tooltip: 'Limpiar mapa',
            onPressed: () {
              final recorridoVM = context.read<RecorridoViewModel>();
              recorridoVM.resetearTodo();
              setState(() {
                _rutaSeleccionadaId = null;
                _textoBusqueda = "Buscar";
                _destinoSeleccionado = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // 🟦 Mensaje de cambio de modo
  Widget _buildModoMensaje() => Positioned(
        top: 70,
        left: 40,
        right: 40,
        child: AnimatedOpacity(
          opacity: mostrandoMensaje ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
      );
}