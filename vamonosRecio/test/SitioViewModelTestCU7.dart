import 'package:flutter_test/flutter_test.dart';
import 'package:vamonos_recio/vistamodelos/SitioViewModel.dart';

void main() {
  test('CU-7 - Seguimiento de trayecto de Taxi', () async {
    final vm = SitioViewModel();

    // Ejecutamos la simulación
    await vm.pruebaUnitariaCu7Simulada();

    // ✅ Al final del CU-7:
    // 1) El seguimiento del trayecto debe estar detenido
    expect(vm.seguimientoTrayectoTaxiActivo, isFalse);

    // 2) Debe haberse marcado la llegada automática al destino
    expect(vm.llegoAutomaticamenteDestinoTaxi, isTrue);

    // 3) Deben existir valores de distancia/tiempo estimados (último tramo)
    expect(vm.distanciaAprox, isNotNull);
    expect(vm.tiempoEstimado, isNotNull);
  });
}