import 'package:flutter_test/flutter_test.dart';
import 'package:vamonos_recio/vistamodelos/SitioViewModel.dart';

void main() {
  test('CU-9 – Seguimiento de trayecto a pie hacia el sitio mas cercano', () async {
    final vm = SitioViewModel();

    await vm.pruebaUnitariaCu9Simulada();

    // Al final de la simulación:
    expect(vm.seguimientoTaxiActivo, false);          // se detuvo el seguimiento
    expect(vm.llegoAutomaticamenteTaxi, true);        // se marcó llegada automática
    expect(vm.distanciaCaminando, isNotNull);         // se actualizaron datos
    expect(vm.tiempoCaminando, isNotNull);
  });
}