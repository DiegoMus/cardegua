// lib/main.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'productores_page.dart' show ProductorAdapter;
import 'parcelas_page.dart' show ParcelaAdapter;
import 'auth_page.dart';
import 'productores_page.dart';
import 'parcelas_page.dart';

Future<void> main() async {
  // Ejecutar toda la inicialización en la misma zone donde luego llamaremos runApp.
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Inicializar Hive
      await Hive.initFlutter();

      // Inicializar Supabase (ajusta url/anonKey si es necesario)
      await Supabase.initialize(
        url: 'https://jpvtmqnfaeptedozvoxe.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpwdnRtcW5mYWVwdGVkb3p2b3hlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4OTg0MjgsImV4cCI6MjA3NTQ3NDQyOH0.KV2YIxcoCadWVcRhdXwKtHObCVXNPwJ-FedAmV4C3pg',
      );

      runApp(const MyApp());
    },
    (error, stack) {
      // Captura errores no manejados
      developer.log('runZonedGuarded caught: $error', name: 'main');
      developer.log(stack.toString(), name: 'main');
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final bool _runConnectivityTest = true;

  @override
  void initState() {
    super.initState();
    if (_runConnectivityTest) {
      _testHost('https://jpvtmqnfaeptedozvoxe.supabase.co');
    }
  }

  Future<void> _testHost(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
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
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFFB2D8B2),
        ),
        fontFamily: 'Montserrat',
      ),
      home: const AuthPage(),
    );
  }
}
