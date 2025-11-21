import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:vamonos_recio/vistamodelos/HomeViewModel.dart';
import 'package:vamonos_recio/vistamodelos/RecorridoViewModel.dart';
import 'package:vamonos_recio/vistamodelos/SitioViewModel.dart';
import 'package:vamonos_recio/vistamodelos/TraficoViewModel.dart';

import '../services/MapService.dart';
import 'BusquedaView.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  GoogleMapController? mapController;

  @override
  void initState() {
    super.initState();
    // Inicializar la lógica del Home desde el ViewModel
    final homeVM = context.read<HomeViewModel>();
    homeVM.inicializarHome();
  }

  @override
  Widget build(BuildContext context) {
    final homeVM = context.watch<HomeViewModel>();
    final recorridoVM = context.watch<RecorridoViewModel>();
    final sitioVM = context.watch<SitioViewModel>();
    final traficoVM = context.watch<TraficoViewModel>();
    final primary = const Color(0xFF137fec);

    // ⭐ Hacer que la cámara siga al usuario cuando el seguimiento está activo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 📍 Seguir al usuario mientras el seguimiento CU-8 está activo
      if (recorridoVM.seguimientoActivo &&
          recorridoVM.ubicacionActual != null &&
          mapController != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLng(recorridoVM.ubicacionActual!),
        );
      }

      // 📍 Seguir al usuario mientras el seguimiento CU-9 está activo
      if (sitioVM.seguimientoTaxiActivo &&
          sitioVM.ubicacionActual != null &&
          mapController != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLng(sitioVM.ubicacionActual!),
        );
      }

      // ✅ Diálogo de llegada automática a la parada (CU-8)
      if (recorridoVM.llegoAutomaticamente) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Has llegado a la parada"),
            content: const Text(
              "Has llegado a la parada más cercana. "
              "Ahora puedes esperar tu transporte.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Aceptar"),
              ),
            ],
          ),
        );

        recorridoVM.marcarDialogoLlegadaMostrado();
      }

      // ✅ Diálogo de llegada automática al sitio de taxis (CU-9)
      if (sitioVM.llegoAutomaticamenteTaxi) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Has llegado al sitio de taxis"),
            content: const Text(
              "Has llegado al sitio de taxis más cercano. "
              "Ahora puedes abordar tu taxi.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Aceptar"),
              ),
            ],
          ),
        );

        sitioVM.marcarDialogoLlegadaTaxiMostrado();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🗺️ Mapa principal
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: MapService.centroZacatecas,
                zoom: 13,
              ),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (pos) async {
                await homeVM.onCameraMove(pos.zoom);
              },
              markers: homeVM.switchModo
                  ? sitioVM.markers
                  : recorridoVM.marcadores,
              polylines: homeVM.switchModo
                  ? sitioVM.polylines
                  : recorridoVM.polylines.union(recorridoVM.rutaCaminando),
              // OCULTAR PARADAS O SITIOS CUANDO HACE SEGUIMIENTO
              circles: (!homeVM.switchModo && homeVM.ocultarParadas) ? <Circle>{} : (homeVM.switchModo && homeVM.ocultarSitios) ? <Circle>{} : homeVM.circulos,
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
                      CameraUpdate.newLatLngZoom(destino, 15),
                    );

                    final homeVM = context.read<HomeViewModel>();
                    final recorridoVM = context.read<RecorridoViewModel>();
                    final sitioVM = context.read<SitioViewModel>();

                    await homeVM.marcarDestino(
                      destino,
                      recorridoVM: recorridoVM,
                      sitioVM: sitioVM,
                      apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8',
                    );

                    // Actualizar el texto de búsqueda con el nombre del destino
                    homeVM.textoBusqueda = nombre;
                    homeVM.notifyListeners();
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
                          homeVM.textoBusqueda,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 🚕 Info del viaje taxi
            if (homeVM.switchModo && sitioVM.tiempoEstimado != null)
              const Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: TaxiInfoDropdown(),
              ),

            // 🚶‍♂️ Botón para ver info de caminata al sitio de taxi
            if (homeVM.switchModo &&
                sitioVM.sitioMasCercano != null &&
                sitioVM.tiempoCaminando != null &&
                sitioVM.distanciaCaminando != null)
              Positioned(
                bottom: 150,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: false,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: TaxiWalkingPopup(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Ver ruta a pie'),
                  ),
                ),
              ),

            // 🧭 Dropdown rutas (solo modo rutas)
            if (!homeVM.switchModo &&
                homeVM.destinoSeleccionado != null &&
                recorridoVM.rutasCandidatas.isNotEmpty)
              Positioned(
                top: 70,
                left: 12,
                right: 12,
                child: _buildDropdown(recorridoVM, homeVM),
              ),

            // 🚶‍♂️ Botón para ver info de caminata hacia la parada (CU-8)
            if (!homeVM.switchModo &&
                recorridoVM.paradaMasCercana != null &&
                recorridoVM.tiempoCaminando != null &&
                recorridoVM.distanciaCaminando != null)
              Positioned(
                bottom: 150, // ajusta si se empalma con los FAB
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: false,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: WalkingInfoPopup(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Ver ruta a pie'),
                  ),
                ),
              ),

            // 🟦 Mensaje de modo
            if (homeVM.mostrandoMensaje) _buildModoMensaje(),

            // 🔁 Botón cambiar modo
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: primary,
                onPressed: () async {
                  final recorridoVM = context.read<RecorridoViewModel>();
                  final sitioVM = context.read<SitioViewModel>();
                  await homeVM.toggleModo(
                    recorridoVM: recorridoVM,
                    sitioVM: sitioVM,
                  );
                },
                child: Icon(
                  homeVM.switchModo
                      ? Icons.directions_bus
                      : Icons.local_taxi,
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
                    traficoVM.trafficEnabled ? Icons.traffic : Icons.map,
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
  Widget _buildDropdown(
    RecorridoViewModel recorridoVM,
    HomeViewModel homeVM,
  ) {
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
                value: homeVM.rutaSeleccionadaId,
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
                        vertical: 8,
                        horizontal: 12,
                      ),
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
                          const Icon(
                            Icons.directions_bus,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (valor) async {
                  if (valor != null) {
                    homeVM.rutaSeleccionadaId = valor;
                    homeVM.notifyListeners();

                    await recorridoVM.dibujarRutaDesdeBD(int.parse(valor));

                    // 🧭 CU-4: Calcular parada más cercana automáticamente al elegir ruta
                    if (homeVM.ubicacionActual != null) {
                      recorridoVM.setUbicacionActual(
                        homeVM.ubicacionActual!,
                      );

                      await recorridoVM.obtenerParadaMasCercana(
                        int.parse(valor),
                      );

                      if (recorridoVM.paradaMasCercana != null) {
                        await recorridoVM.calcularRutaCaminando(
                          origen: homeVM.ubicacionActual!,
                          destino: LatLng(
                            recorridoVM.paradaMasCercana!.latitud,
                            recorridoVM.paradaMasCercana!.longitud,
                          ),
                          apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8',
                        );
                      }
                    }
                  }
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              final recorridoVM = context.read<RecorridoViewModel>();
              homeVM.limpiarSeleccionRutas(recorridoVM);
            },
          ),
        ],
      ),
    );
  }

  // 🔹 Mensaje de modo actual
  Widget _buildModoMensaje() {
    final homeVM = context.watch<HomeViewModel>();

    return Positioned(
      top: 70,
      left: 40,
      right: 40,
      child: AnimatedOpacity(
        opacity: homeVM.mostrandoMensaje ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black87.withOpacity(0.75),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              homeVM.switchModo ? "Modo Taxi" : "Modo Transporte Público",
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
}

// 🔻 A partir de aquí, tus popups quedan IGUALES (ya usaban otros ViewModels)

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.local_taxi),
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
                          onPressed: () =>
                              setState(() => _expandido = false),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          onPressed: () {
                            context.read<SitioViewModel>().limpiarMapaTaxi();
                          },
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInfoRowTaxi("Sitio más cercano:", sitio),
                _buildInfoRowTaxi("Tiempo estimado:", tiempo),
                _buildInfoRowTaxi("Distancia:", distancia),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() => _expandido = true),
                  child: const Row(
                    children: [
                      Icon(Icons.local_taxi),
                      SizedBox(width: 8),
                      Text(
                        "Trayecto de Taxi",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ],
                  ),
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

  Widget _buildInfoRowTaxi(String label, String value) => Padding(
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

// 🚶 Popup caminata hacia la parada más cercana (CU-4 + botón para CU-8)
class WalkingInfoPopup extends StatelessWidget {
  const WalkingInfoPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final recorridoVM = context.watch<RecorridoViewModel>();
    final parada = recorridoVM.paradaMasCercana?.nombre ?? "—";
    final tiempo = recorridoVM.tiempoCaminando ?? "—";
    final distancia = recorridoVM.distanciaCaminando ?? "—";

    // Si no hay datos, no mostramos nada (sheet de altura 0)
    if (recorridoVM.paradaMasCercana == null ||
        recorridoVM.tiempoCaminando == null ||
        recorridoVM.distanciaCaminando == null) {
      return const SizedBox.shrink();
    }

    final seguimientoActivo =
        context.watch<RecorridoViewModel>().seguimientoActivo;

    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con título y X (sin minimizar)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_walk),
                  SizedBox(width: 8),
                  Text(
                    "Ruta a pie",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  // Solo cerramos el bottom sheet, NO limpiamos datos
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 10),
          _buildInfoRow("Parada más cercana:", parada),
          _buildInfoRow("Tiempo estimado:", tiempo),
          _buildInfoRow("Distancia:", distancia),

          const SizedBox(height: 16),

          // 🔘 Botón para iniciar / detener CU-8 (seguimiento a pie hacia la parada)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final vm = context.read<RecorridoViewModel>();
                final homeVM = context.read<HomeViewModel>();

                if (!vm.seguimientoActivo) {
                  // 👉 Iniciar seguimiento: escondemos circles de paradas
                  homeVM.setOcultarParadas(true);

                  await vm.iniciarSeguimientoAPieParada(
                    apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8',
                  );
                } else {
                  await vm.detenerSeguimientoAPie();
                  homeVM.setOcultarParadas(false);
                }

                // Volver al mapa
                Navigator.of(context).pop();
              },
              icon: Icon(
                seguimientoActivo ? Icons.stop : Icons.play_arrow,
              ),
              label: Text(
                seguimientoActivo
                    ? "Detener seguimiento"
                    : "Iniciar seguimiento a pie",
              ),
            ),
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
            Text(value),
          ],
        ),
      );
}

// 🚕 Popup caminata hacia sitio de taxi (CU-5 + botón para CU-9)
class TaxiWalkingPopup extends StatelessWidget {
  const TaxiWalkingPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final sitioVM = context.watch<SitioViewModel>();
    final sitio = sitioVM.sitioMasCercano?.nombre ?? "—";
    final tiempo = sitioVM.tiempoCaminando ?? "—";
    final distancia = sitioVM.distanciaCaminando ?? "—";

    // Si no hay datos, no mostramos nada (sheet de altura 0)
    if (sitioVM.sitioMasCercano == null ||
        sitioVM.tiempoCaminando == null ||
        sitioVM.distanciaCaminando == null) {
      return const SizedBox.shrink();
    }

    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con título y X (sin minimizar)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_walk,
                      color: Color.fromARGB(255, 0, 0, 0)),
                  SizedBox(width: 8),
                  Text(
                    "Ruta a pie",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  // Solo cerramos el bottom sheet, NO limpiamos datos
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 10),
          _buildInfoRow("Sitio más cercano:", sitio),
          _buildInfoRow("Tiempo estimado:", tiempo),
          _buildInfoRow("Distancia:", distancia),

                    const SizedBox(height: 16),

          // 🔘 Botón para iniciar / detener CU-9 (seguimiento a pie)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final sitioVM = context.read<SitioViewModel>();
                final homeVM = context.read<HomeViewModel>();

                if (!sitioVM.seguimientoTaxiActivo) {
                  // Iniciar seguimiento: escondemos círculos de sitios
                  homeVM.setOcultarSitios(true);

                  await sitioVM.iniciarSeguimientoAPieSitioTaxi(
                    apiKey: 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8',
                  );
                } else {
                // Detener seguimiento manualmente: volvemos a mostrar sitios
                await sitioVM.detenerSeguimientoAPieSitioTaxi();
                homeVM.setOcultarSitios(false);
                }

                // Volver al mapa
                Navigator.of(context).pop();
              },
              icon: Icon(
                context.watch<SitioViewModel>().seguimientoTaxiActivo
                ? Icons.stop
                : Icons.play_arrow,
              ),
              label: Text(
                context.watch<SitioViewModel>().seguimientoTaxiActivo
                ? "Detener seguimiento"
                : "Iniciar seguimiento a pie",
              ),
            ),
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
            Text(value),
          ],
        ),
      );
}