import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modelos/RutaModel.dart';
import 'services/DatabaseHelper.dart';
import 'services/DirectionsService.dart';
import 'services/RoutePrecomputeService.dart';

import 'vistamodelos/SitioViewModel.dart';
import 'vistamodelos/TraficoViewModel.dart';
import 'vistamodelos/RecorridoViewModel.dart';
import 'vistamodelos/BusquedaViewModel.dart';
import 'vistamodelos/HomeViewModel.dart';
import 'vistas/HomeView.dart';

/// Ejecuta el precompute solo para las rutas que NO tienen polyline guardada
Future<void> precomputarRutasSiHaceFalta() async {
  final db = DatabaseHelper();

  // 1) Obtener todas las rutas desde la BD
  final List<RutaModel> rutas = await db.obtenerRutas();
  print('🔍 Rutas en BD: ${rutas.length}');

  // 2) Filtrar solo las que no tengan POLYLINE aún
  final List<int> idsSinPolyline = rutas
      .where((r) => r.polyline.isEmpty && r.idRuta != null)
      .map((r) => r.idRuta!)
      .toList();

  print('👉 Rutas sin polyline: $idsSinPolyline');

  if (idsSinPolyline.isEmpty) {
    print('✅ Todas las rutas ya tienen polyline, no hay nada que precomputar.');
    return;
  }

  // 3) Crear servicios
  const apiKey = 'AIzaSyDkcaTrFPn2PafDX85VmT-XEKS2qnk7oe8'; // tu API key

  final directions = DirectionsService(apiKey);
  final precomputeService =
      RoutePrecomputeService(db: db, directions: directions);

  // 4) Ejecutar precompute para las rutas que faltan
  await precomputeService.precomputarTodasLasRutas(idsSinPolyline);
  print('🏁 precomputarRutasSiHaceFalta() terminado');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Antes de arrancar la app, precomputamos si hace falta
  await precomputarRutasSiHaceFalta();

   // 🔍 DEBUG: ver si se guardaron las polylines
  final db = DatabaseHelper();
  await db.debugImprimirTamanosPolylines();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        ChangeNotifierProvider(create: (_) => RecorridoViewModel()),
        ChangeNotifierProvider(create: (_) => SitioViewModel()),
        ChangeNotifierProvider(create: (_) => BusquedaViewModel()),
        ChangeNotifierProvider(create: (_) => TraficoViewModel()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vamonos Recio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const HomeView(),
    );
  }
}
