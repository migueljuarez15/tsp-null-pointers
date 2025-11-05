import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../modelos/ParadaModel.dart';
import '../modelos/RutaModel.dart';
import '../modelos/RecorridoModel.dart';
import '../services/DatabaseHelper.dart';
import '../services/OSRMService.dart';
import 'dart:math';

class RecorridoViewModel extends ChangeNotifier {
  final _db = DatabaseHelper();

  Set<Polyline> polylines = {};
  Set<Marker> marcadores = {};
  bool cargando = false;

  /// 🔹 Dibuja la ruta completa (según los registros de BD)
  Future<void> dibujarRutaDesdeBD(int idRuta) async {
    cargando = true;
    notifyListeners();

    try {
      // 1️⃣ Obtener datos base desde la BD
      final recorridos = await _db.obtenerRecorridos();
      final paradas = await _db.obtenerParadas();
      final rutas = await _db.obtenerRutas();

      // 2️⃣ Filtrar los recorridos de esa ruta y ordenarlos
      final recorridosRuta = recorridos
          .where((r) => r.idRuta == idRuta)
          .toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

      if (recorridosRuta.isEmpty) {
        debugPrint("❌ No hay registros de recorrido para la ruta $idRuta.");
        return;
      }

      final ruta = rutas.firstWhere((r) => r.idRuta == idRuta);

      // 3️⃣ Convertir a lista de paradas ordenadas
      List<ParadaModel> paradasRuta = [];
      for (var r in recorridosRuta) {
        final p = paradas.firstWhere((p) => p.idParada == r.idParada);
        paradasRuta.add(p);
      }

      // 4️⃣ Consultar OSRM para cada tramo consecutivo
      List<LatLng> puntosTotales = [];
      for (int i = 0; i < paradasRuta.length - 1; i++) {
        final origen = LatLng(paradasRuta[i].latitud, paradasRuta[i].longitud);
        final destino = LatLng(paradasRuta[i + 1].latitud, paradasRuta[i + 1].longitud);

        final puntosSegmento = await OSRMService.obtenerRutaOSRM(origen, destino);
        if (puntosSegmento.isNotEmpty) {
          puntosTotales.addAll(puntosSegmento);
        } else {
          // En caso de fallo en OSRM, se conecta directo
          puntosTotales.addAll([origen, destino]);
        }
      }

      // 5️⃣ Dibujar la polyline
      polylines = {
        Polyline(
          polylineId: PolylineId('ruta_$idRuta'),
          points: puntosTotales,
          color: _colorDesdeHex(ruta.color),
          width: 6,
        )
      };

      // 6️⃣ Agregar marcadores para inicio y fin
      marcadores = {
        Marker(
          markerId: const MarkerId('inicio'),
          position: LatLng(paradasRuta.first.latitud, paradasRuta.first.longitud),
          infoWindow: InfoWindow(title: "Inicio: ${paradasRuta.first.nombre}"),
        ),
        Marker(
          markerId: const MarkerId('fin'),
          position: LatLng(paradasRuta.last.latitud, paradasRuta.last.longitud),
          infoWindow: InfoWindow(title: "Fin: ${paradasRuta.last.nombre}"),
        ),
      };

      debugPrint("✅ Ruta ${ruta.nombre} trazada correctamente con ${puntosTotales.length} puntos.");

    } catch (e) {
      debugPrint("⚠️ Error al dibujar ruta desde BD: $e");
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Utilidad: convertir color HEX de BD a Color Flutter
  Color _colorDesdeHex(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 6) hexColor = "FF$hexColor";
    return Color(int.parse("0x$hexColor"));
  }
}
