// PlacesService.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/MapService.dart';

class PlacesService {
  final String apiKey = "AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8";

  Future<List<String>> obtenerSugerencias(String input) async {
    if (input.isEmpty) return [];

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?'
      'input=$input'
      '&components=country:mx'
      '&location=22.77,-102.57'
      '&radius=15000'
      '&key=$apiKey',
    );

    final response = await http.get(url);
    final data = json.decode(response.body);

    if (data['status'] != 'OK') return [];

    return List<String>.from(
      data['predictions'].map((p) => p['description']),
    );
  }

  Future<LatLng?> obtenerCoordenadas(String placeId) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json?'
      'place_id=$placeId&fields=geometry&key=$apiKey',
    );

    final response = await http.get(url);
    final data = json.decode(response.body);

    if (data['status'] != 'OK') return null;

    final location = data['result']['geometry']['location'];
    final lat = location['lat'];
    final lng = location['lng'];

    // Validamos que esté dentro del área
    if (!MapService().estaDentroDeZona(lat, lng)) {
      return null;
    }

    return LatLng(lat, lng);
  }
}