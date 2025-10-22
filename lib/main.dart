import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart'; // ajusta la ruta si tu AuthPage está en otra ubicación

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Supabase (usa tu URL y anonKey)
  await Supabase.initialize(
    url: 'https://jpvtmqnfaeptedozvoxe.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpwdnRtcW5mYWVwdGVkb3p2b3hlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4OTg0MjgsImV4cCI6MjA3NTQ3NDQyOH0.KV2YIxcoCadWVcRhdXwKtHObCVXNPwJ-FedAmV4C3pg',
  );

  // Manejo global de errores de Flutter (UI)
  FlutterError.onError = (FlutterErrorDetails details) {
    // Mostrar error como siempre
    FlutterError.presentError(details);
    // Además log completo para depuración
    debugPrint('FlutterError.onError: ${details.exceptionAsString()}');
    debugPrint(details.stack?.toString() ?? 'No stack available');
  };

  // Manejo global de errores en isolates / PlatformDispatcher
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher.onError: $error');
    debugPrint(stack.toString());
    // devolver true evita que el framework termine el app automáticamente
    return true;
  };

  // Zona para capturar errores asíncronos no manejados
  runZonedGuarded<Future<void>>(() async {
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('runZonedGuarded caught: $error');
    debugPrint(stack.toString());
  });
}

/// App principal (usa AuthPage como pantalla inicial).
/// Si ya tienes tu propio MyApp en main.dart, reemplaza solo la función main()
/// por la anterior y conserva tu MyApp.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Cambia por false cuando ya no necesites la prueba de conectividad.
  final bool _runConnectivityTest = true;

  @override
  void initState() {
    super.initState();
    if (_runConnectivityTest) {
      // prueba rápida para ver si el host responde (imprime en logs)
      _testHost('https://jpvtmqnfaeptedozvoxe.supabase.co');
    }
  }

  Future<void> _testHost(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      developer.log('testHost status: ${r.statusCode}', name: 'connectivity');
      final snippet = r.body.length > 200 ? r.body.substring(0, 200) : r.body;
      developer.log('body snippet: $snippet', name: 'connectivity');
    } catch (e, st) {
      developer.log('testHost error: $e', name: 'connectivity');
      developer.log(st.toString(), name: 'connectivity');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF6DB571),
        colorScheme: ColorScheme.fromSwatch().copyWith(secondary: const Color(0xFFB2D8B2)),
        fontFamily: 'Montserrat',
      ),
      home: const AuthPage(),
    );
  }
}