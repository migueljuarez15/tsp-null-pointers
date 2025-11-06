import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vamonos_recio/vistamodelos/SitioViewModel.dart';
import 'vistas/HomeView.dart';
import 'vistamodelos/RecorridoViewModel.dart';
import 'vistamodelos/BusquedaViewModel.dart';
import 'vistamodelos/HomeViewModel.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        ChangeNotifierProvider(create: (_) => RecorridoViewModel()),
        ChangeNotifierProvider(create: (_) => SitioViewModel()),
        ChangeNotifierProvider(create: (_) => BusquedaViewModel()),
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
      title: 'Transporte ZAC-GPE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const HomeView(),
    );
  }
}