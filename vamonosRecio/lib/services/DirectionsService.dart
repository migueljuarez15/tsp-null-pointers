// lib/services/DirectionsService.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class DirectionsService {
  final String apiKey;

  DirectionsService(this.apiKey);

  /// Obtiene una lista de puntos LatLng para la ruta entre origen y destino
  Future<List<LatLng>> obtenerSegmentoRuta({
    required LatLng origen,
    required LatLng destino,
    String mode = 'driving', // o 'transit'
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origen.latitude},${origen.longitude}'
      '&destination=${destino.latitude},${destino.longitude}'
      '&mode=$mode'
      '&key=$apiKey',
    );

    final resp = await http.get(url);

    if (resp.statusCode != 200) {
      throw Exception('Error Directions: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);

    if (data['routes'] == null || (data['routes'] as List).isEmpty) {
      throw Exception('Directions no devolvió rutas');
    }

    final polylineCodificada =
        data['routes'][0]['overview_polyline']['points'] as String;

    // 👇 Versión 3.x: el constructor pide apiKey
    final polylinePoints = PolylinePoints(apiKey: apiKey);

    final decoded = PolylinePoints.decodePolyline(polylineCodificada);

    return decoded
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }
}