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
  LatLng? _ubicacionActual;
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

  /// 📍 Marca el destino y lo comunica al ViewModel
  void _marcarDestino(LatLng destino) async {
    final recorridoVM = context.read<RecorridoViewModel>();
    setState(() => _destinoSeleccionado = destino);
    recorridoVM.marcarDestino(destino);
    // 🔹 Aquí está la clave: buscar rutas cercanas al destino
    await recorridoVM.buscarRutasCercanas(destino);
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
              initialCameraPosition: CameraPosition(
                target: MapService.centroZacatecas,
                zoom: 13,
              ),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (position) async {
                _zoomActual = position.zoom;
                if (!switchModo) await _cargarParadasOptimizado();
              },
              markers: recorridoVM.marcadores,
              polylines: recorridoVM.polylines,
              circles: _circulos,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
            ),

            /// 🔍 Barra de búsqueda
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

                    _marcarDestino(destino);

                    // ⚙️ Solo si estamos en modo camión, dibuja la ruta completa
                    /*if (!switchModo) {
                      await recorridoVM.dibujarRutaDesdeBD(1);
                    }*/

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
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// 🧭 Dropdown de rutas cercanas
            if (_destinoSeleccionado != null && recorridoVM.rutasCandidatas.isNotEmpty)
              Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _rutaSeleccionadaId,
                      hint: const Text("Selecciona una ruta cercana"),
                      items: recorridoVM.rutasCandidatas.map((ruta) {
                        return DropdownMenuItem<String>(
                          value: ruta.idRuta.toString(),
                          child: Text(ruta.nombre),
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
              ),

            /// 🟦 Mensaje de modo
            if (mostrandoMensaje)
              Positioned(
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
              ),

            /// 🔁 Botón de modo
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
}
