import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:vamonos_recio/modelos/ParadaModel.dart';
import 'package:vamonos_recio/modelos/SitioModel.dart';
import 'package:vamonos_recio/vistamodelos/HomeViewModel.dart';
import 'package:vamonos_recio/vistamodelos/RecorridoViewModel.dart';
import 'package:vamonos_recio/vistamodelos/SitioViewModel.dart';
import 'package:vamonos_recio/vistamodelos/TraficoViewModel.dart';
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
  LatLng? _ubicacionActual;

  List<ParadaModel> _todasParadas = [];
  List<SitioModel> _todosSitios = [];
  Set<Circle> _circulos = {};
  Set<Marker> _markers = {};
  Set<Polyline> _rutas = {};

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
    _todasParadas = await _db.obtenerParadas();

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
          }
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  Future<void> _cargarSitiosOptimizado() async {
    _todosSitios = await _db.obtenerSitios();

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
          fillColor:
              const Color.fromARGB(255, 236, 76, 76).withOpacity(0.5),
          strokeColor: const Color.fromARGB(255, 255, 44, 44),
          strokeWidth: 1,
          consumeTapEvents: true,
          onTap: () { 
            ScaffoldMessenger.of(context).showSnackBar( 
              SnackBar(content: Text(s.nombre)),
            );
          }
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  // 🔁 Modo Transporte ↔ Taxi (versión fusionada)
  Future<void> _toggleModo() async {
    final recorridoVM = context.read<RecorridoViewModel>();
    final sitioVM = context.read<SitioViewModel>();

    // Limpieza total del mapa
    recorridoVM.resetearTodo();
    sitioVM.limpiarMapaTaxi();

    setState(() {
      _rutaSeleccionadaId = null;
      _textoBusqueda = "Buscar";
      _destinoSeleccionado = null;
      _markers.clear();
      _circulos.clear();
      switchModo = !switchModo;
      mostrandoMensaje = true;
    });

    await _cargarContenido();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  // 📍 Lógica de marcar destino (CU1 y CU2 fusionados)
  Future<void> _marcarDestino(LatLng destino) async {
    _ubicacionActual ??= const LatLng(22.7700, -102.5720);

    if (switchModo) {
      // 🚕 Lógica modo taxi
      final sitioVM = context.read<SitioViewModel>();
      await sitioVM.cargarSitios();
      final sitio = await sitioVM.obtenerSitioMasCercano(_ubicacionActual!);
      if (sitio != null) {
        await sitioVM.calcularRutaTaxi(
          origen: LatLng(sitio.latitud, sitio.longitud),
          destino: destino,
          apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8',
        );
      }
    } else {
      // 🚌 Lógica transporte público
      final recorridoVM = context.read<RecorridoViewModel>();
      recorridoVM.marcarDestino(destino);
      await recorridoVM.buscarRutasCercanas(destino);
    }

    setState(() {
      _destinoSeleccionado = destino;
      _textoBusqueda = "Destino seleccionado";
    });
  }

  @override
  Widget build(BuildContext context) {
    final recorridoVM = context.watch<RecorridoViewModel>();
    final sitioVM = context.watch<SitioViewModel>();
    final traficoVM = context.watch<TraficoViewModel>();
    final primary = const Color(0xFF137fec);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🗺️ Mapa principal
            GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: MapService.centroZacatecas, zoom: 13),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (pos) async {
                _zoomActual = pos.zoom;
                await _cargarContenido();
              },
              markers: switchModo
                  ? sitioVM.markers
                  : recorridoVM.marcadores.union(_markers),
              polylines: switchModo
                  ? sitioVM.polylines
                  : recorridoVM.polylines.union(_rutas),
              circles: _circulos,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              trafficEnabled: traficoVM.trafficEnabled,
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
                    final LatLng destino = resultado['coordenadas'];
                    final String nombre = resultado['nombre'];

                    mapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(destino, 15));
                    await _marcarDestino(destino);

                    setState(() => _textoBusqueda = nombre);
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
                              fontSize: 16, color: Colors.grey[700]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 🚕 Popup taxi
            if (switchModo)
              const Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: TaxiInfoDropdown(),
              ),

            // 🧭 Dropdown rutas (solo modo rutas)
            if (!switchModo &&
                _destinoSeleccionado != null &&
                recorridoVM.rutasCandidatas.isNotEmpty)
              Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: _buildDropdown(recorridoVM),
              ),

            // 🟦 Mensaje de modo
            if (mostrandoMensaje) _buildModoMensaje(),

            // 🔁 Botón cambiar modo
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

            // 🛣️ Botón de tráfico
            Positioned(
              bottom: 92,
              right: 24,
              child: GestureDetector(
                onTap: () => traficoVM.mostrarMapaTrafico(context),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: traficoVM.trafficEnabled
                      ? Colors.green
                      : Colors.yellow[700],
                  child: Icon(
                    traficoVM.trafficEnabled
                        ? Icons.traffic
                        : Icons.map,
                    color: Colors.white,
                  ),
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

  // 🔹 Dropdown rutas transporte
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
                value: _rutaSeleccionadaId,
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
            icon: const Icon(Icons.close),
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

  // 🔹 Mensaje de modo actual
  Widget _buildModoMensaje() => Positioned(
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
                    ? "Modo Taxi"
                    : "Modo Transporte Público",
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      );
}

// 🚕 Popup taxi minimizable y con “X” persistente
class TaxiInfoDropdown extends StatefulWidget {
  const TaxiInfoDropdown({super.key});

  @override
  State<TaxiInfoDropdown> createState() => _TaxiInfoDropdownState();
}

class _TaxiInfoDropdownState extends State<TaxiInfoDropdown> {
  bool _expandido = true;

  @override
  Widget build(BuildContext context) {
    final sitioVM = context.watch<SitioViewModel>();
    final sitio = sitioVM.sitioMasCercano?.nombre ?? "N/A";
    final tiempo = sitioVM.tiempoEstimado ?? "—";
    final distancia = sitioVM.distanciaAprox ?? "—";

    if (sitioVM.tiempoEstimado == null && sitioVM.distanciaAprox == null) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: _expandido
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(children: [
                        Icon(Icons.local_taxi),
                        SizedBox(width: 8),
                        Text("Trayecto de Taxi",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                      ]),
                      Row(children: [
                        IconButton(
                          onPressed: () =>
                              setState(() => _expandido = false),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          onPressed: () {
                            context.read<SitioViewModel>().limpiarMapaTaxi();
                          },
                          icon:
                              const Icon(Icons.close, color: Colors.grey),
                        ),
                      ])
                    ]),
                const SizedBox(height: 10),
                _buildInfoRow("Sitio más cercano:", sitio),
                _buildInfoRow("Tiempo estimado:", tiempo),
                _buildInfoRow("Distancia:", distancia),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() => _expandido = true),
                  child: const Row(children: [
                    Icon(Icons.local_taxi),
                    SizedBox(width: 8),
                    Text("Trayecto de Taxi",
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 18)),
                    Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                  ]),
                ),
                IconButton(
                  onPressed: () {
                    context.read<SitioViewModel>().limpiarMapaTaxi();
                  },
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(value)
            ]),
      );
}
