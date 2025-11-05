import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../vistamodelos/BusquedaViewModel.dart';

class BusquedaView extends StatefulWidget {
  const BusquedaView({super.key});

  @override
  State<BusquedaView> createState() => _BusquedaViewState();
}

class _BusquedaViewState extends State<BusquedaView> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<BusquedaViewModel>(context);
    final primary = const Color(0xFF137fec);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Buscar destino',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🧭 Caja principal de inicio/destino
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Column(
                children: [
                  // 🔹 INICIO (Ubicación actual)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.circle, color: Colors.blue, size: 12),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Inicio",
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Ubicación actual",
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.close, color: Colors.transparent, size: 20),
                    ],
                  ),
                  const Divider(height: 8, thickness: 0.5),

                  // 🔹 DESTINO (Input con botón de limpiar)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.circle_outlined,
                          color: Colors.blue, size: 12),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Destino",
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 2),
                            TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: "Introduce tu destino",
                                border: InputBorder.none,
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                                suffixIcon: _controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.grey, size: 20),
                                        onPressed: () {
                                          _controller.clear();
                                          viewModel.sugerencias.clear();
                                          viewModel.notifyListeners();
                                        },
                                      )
                                    : null,
                              ),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                              onChanged: (value) =>
                                  viewModel.obtenerSugerencias(value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 🔽 Lista de sugerencias
            if (viewModel.sugerencias.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: viewModel.sugerencias.length,
                  itemBuilder: (context, index) {
                    final sugerencia = viewModel.sugerencias[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined,
                          color: Colors.grey),
                      title: Text(
                        sugerencia,
                        style: GoogleFonts.plusJakartaSans(),
                      ),
                      onTap: () async {
                        await viewModel.seleccionarDestino(sugerencia);
                        if (viewModel.destinoSeleccionado != null) {
                          // ⬅️ Devolvemos LatLng y nombre al HomeView
                          Navigator.pop(context, {
                            'nombre': sugerencia,
                            'coordenadas': viewModel.destinoSeleccionado,
                          });
                        } else if (viewModel.mensajeError != null) {
                          // ❌ Pop-up de error elegante
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Error de ubicación",
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  viewModel.mensajeError!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      "Aceptar",
                                      style: GoogleFonts.plusJakartaSans(
                                        color: primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}