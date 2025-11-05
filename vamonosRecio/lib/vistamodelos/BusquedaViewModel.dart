import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/PlacesService.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BusquedaViewModel extends ChangeNotifier {
  final _placesService = PlacesService();
  List<String> sugerencias = [];
  LatLng? destinoSeleccionado;
  String? mensajeError;

  Future<void> obtenerSugerencias(String texto) async {
    sugerencias = await _placesService.obtenerSugerencias(texto);
    notifyListeners();
  }

  Future<void> seleccionarDestino(String placeDescription) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
        'input=$placeDescription&inputtype=textquery&fields=geometry,place_id&key=${_placesService.apiKey}',
      );

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] != 'OK' || data['candidates'].isEmpty) {
        mensajeError = "No se encontró la ubicación.";
        notifyListeners();
        return;
      }

      final placeId = data['candidates'][0]['place_id'];
      destinoSeleccionado = await _placesService.obtenerCoordenadas(placeId);

      if (destinoSeleccionado == null) {
        mensajeError = "Ubicación fuera de la zona metropolitana.";
      } else {
        mensajeError = null;
      }

      notifyListeners();
    } catch (e) {
      mensajeError = "Error al buscar destino: $e";
      notifyListeners();
    }
  }
}