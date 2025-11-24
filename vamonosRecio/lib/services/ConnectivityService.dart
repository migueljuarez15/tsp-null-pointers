// lib/services/ConnectivityService.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  bool _sinConexion = false;
  bool get sinConexion => _sinConexion;

  // callback para avisar a quien use el servicio
  Function(bool sinConexion)? onStatusChange;

  void iniciar() {
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final sinConn = (result == ConnectivityResult.none);
      _sinConexion = sinConn;
      if (onStatusChange != null) {
        onStatusChange!(sinConn);
      }
    }) as StreamSubscription<ConnectivityResult>?;
  }

  Future<bool> checkInicial() async {
    final result = await _connectivity.checkConnectivity();
    _sinConexion = (result == ConnectivityResult.none);
    return _sinConexion;
  }

  void dispose() {
    _subscription?.cancel();
  }
}