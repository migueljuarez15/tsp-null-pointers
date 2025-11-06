import 'package:flutter/material.dart';

class TraficoViewModel extends ChangeNotifier {
  bool _trafficEnabled = false;
  bool get trafficEnabled => _trafficEnabled;

  Future<void> mostrarMapaTrafico(BuildContext context) async {
    try {
      bool apiDisponible = true; 

      if (!apiDisponible) {
        throw Exception('No se pudo cargar la información del tráfico');
      }

      _trafficEnabled = !_trafficEnabled;
      notifyListeners();
    } catch (e) {
      _trafficEnabled = false;
      notifyListeners();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo cargar la información del tráfico. Intenta más tarde.',
          ),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
