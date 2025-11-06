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
  Set<Marker> _markers = {};

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
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(p.nombre))),
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
          fillColor: const Color.fromARGB(255, 236, 76, 76).withOpacity(0.5),
          strokeColor: const Color.fromARGB(255, 255, 44, 44),
          strokeWidth: 1,
          consumeTapEvents: true,
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(s.nombre))),
        ),
      );
    }

    setState(() => _circulos = visibles);
  }

  Future<void> _toggleModo() async {
    final sitioVM = context.read<SitioViewModel>();
    sitioVM.limpiarMapaTaxi();

    setState(() {
      switchModo = !switchModo;
      _rutas.clear();
      _markers.clear();
      _circulos.clear();
      mostrandoMensaje = true;
      _textoBusqueda = "Buscar";
    });

    await _cargarContenido();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => mostrandoMensaje = false);
    });
  }

  Future<void> _marcarDestino(LatLng destino) async {
    _ubicacionActual ??= const LatLng(22.7700, -102.5720);
    final sitioVM = context.read<SitioViewModel>();

    setState(() {
      _destinoSeleccionado = destino;
      _rutas.clear();
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
      _dibujarRutaSimulada(_ubicacionActual!, destino);
    }
  }

  void _dibujarRutaSimulada(LatLng inicio, LatLng destino) {
    final puntos = [
      inicio,
      LatLng((inicio.latitude + destino.latitude) / 2 + 0.002,
          (inicio.longitude + destino.longitude) / 2 - 0.002),
      destino,
    ];

    setState(() {
      _rutas.clear();
      _rutas.add(Polyline(
        polylineId: const PolylineId("ruta_simulada"),
        points: puntos,
        color: Colors.blueAccent,
        width: 5,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final recorridoVM = context.read<RecorridoViewModel>();
    final sitioVM = context.watch<SitioViewModel>();
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
                } else {
                  await _cargarSitiosOptimizado();
                }
              },
              markers: switchModo ? sitioVM.markers : _markers,
              polylines: switchModo ? sitioVM.polylines : _rutas,
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
                    final LatLng destino = resultado['coordenadas'];
                    final String nombre = resultado['nombre'];

                    mapController!.animateCamera(
                      CameraUpdate.newLatLngZoom(destino, 15),
                    );

                    _marcarDestino(destino);

                    if (!switchModo) {
                      await recorridoVM.dibujarRutaDesdeBD(1);
                    }

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

            // 🚖 Popup del taxi
            if (switchModo) const Positioned(
              top: 70,
              left: 12,
              right: 12,
              child: TaxiInfoDropdown(),
            ),

            if (mostrandoMensaje)
              Positioned(
                top: 130,
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
                            ? "Modo Taxi - Sitios Cercanos"
                            : "Modo Transporte Público",
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

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
}

// 🔹 Nuevo Widget del popup
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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _expandido
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 Encabezado principal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.local_taxi, color: Color.fromARGB(255, 0, 0, 0)),
                        SizedBox(width: 8),
                        Text(
                          "Trayecto de Taxi",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(() => _expandido = false),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          onPressed: () {
                            final sitioVM = context.read<SitioViewModel>();
                            sitioVM.limpiarMapaTaxi();
                          },
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                _buildInfoRow("Sitio más cercano:", sitio),
                _buildInfoRow("Tiempo estimado:", tiempo),
                _buildInfoRow("Distancia:", distancia),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 🔹 Parte izquierda (etiqueta + icono)
                InkWell(
                  onTap: () => setState(() => _expandido = true),
                  child: Row(
                    children: const [
                      Icon(Icons.local_taxi, color: Color.fromARGB(255, 0, 0, 0)),
                      SizedBox(width: 8),
                      Text(
                        "Trayecto de Taxi",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ],
                  ),
                ),

                // 🔹 Parte derecha (botón de cerrar SIEMPRE visible)
                IconButton(
                  onPressed: () {
                    final sitioVM = context.read<SitioViewModel>();
                    sitioVM.limpiarMapaTaxi();
                  },
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }
}