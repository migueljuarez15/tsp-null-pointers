// LocationService.dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Solicita permiso de ubicación al usuario si aún no está concedido.
  Future<bool> solicitarPermisoUbicacion() async {
    bool servicioHabilitado;
    LocationPermission permiso;

    // Verifica si el servicio de ubicación está habilitado
    servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      // No está activado el GPS
      return false;
    }

    // Verifica el estado del permiso
    permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        return false; // Usuario lo negó
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      // El usuario negó permanentemente
      return false;
    }

    return true; // Permiso otorgado
  }

  /// Obtiene la ubicación actual (latitud y longitud)
  Future<Position?> getCurrentLocation() async {
    final tienePermiso = await solicitarPermisoUbicacion();
    if (!tienePermiso) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return position;
    } catch (e) {
      print('Error al obtener ubicación: $e');
      return null;
    }
  }

  /// Valida que la ubicación esté dentro de un rango geográfico (ej. Zacatecas-Guadalupe)
  bool validarUbicacion(double lat, double lon) {
    // Ejemplo de rango aproximado (ajusta según tus límites)
    const minLat = 22.68;
    const maxLat = 22.85;
    const minLon = -102.65;
    const maxLon = -102.45;

    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }
}