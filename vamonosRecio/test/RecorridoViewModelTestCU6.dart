// test/recorrido_view_model_cu6_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vamonos_recio/vistamodelos/RecorridoViewModel.dart';

void main() {
  test('CU-6 - Seguimiento de trayecto de Ruta', () async {
    final vm = RecorridoViewModel();

    // Ejecutamos la simulación (esto va a imprimir en consola)
    await vm.pruebaUnitariaCu6Simulada();

    // ✅ Verificaciones clave para el CU-6:
    // 1) El seguimiento debe haberse detenido al final
    expect(vm.seguimientoRutaActivo, isFalse);

    // 2) Se debió marcar llegada automática en algún punto
    expect(vm.llegoAutomaticamenteRuta, isTrue);

    // 3) El aviso anticipado debió activarse en algún momento de la simulación
    //    (después en la app se limpia con marcarAvisoProximoParadaMostrado, pero aquí debe quedar true)
    expect(vm.avisoProximoParada, isTrue);
  });
}