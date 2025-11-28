import 'package:flutter_test/flutter_test.dart';
import 'package:vamonos_recio/vistamodelos/RecorridoViewModel.dart';

void main() {
  test('CU-8 – Seguimiento de trayecto a pie hacia la parada mas cercana', () async {
    final vm = RecorridoViewModel();

    // Ejecutamos la simulación
    await vm.pruebaUnitariaCu8Simulada();

    // ✅ Al final de la simulación:
    //   - El seguimiento debe estar detenido
    //   - Debe haberse marcado la llegada automática
    expect(vm.seguimientoActivo, false);
    expect(vm.llegoAutomaticamente, true);
  });
}