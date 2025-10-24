import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'productores_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    // Espera un momento para que la UI se pinte y Supabase se inicialice
    await Future.delayed(Duration.zero);

    final session = Supabase.instance.client.auth.currentSession;

    // Caso 1: Hay sesión online activa
    if (session != null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProductoresPage()),
        );
      }
      return;
    }

    // Caso 2: No hay sesión online. Revisa si hay datos locales.
    try {
      // Abre una caja clave (como la de catálogos) para ver si hay datos.
      if (!Hive.isBoxOpen('catalog_municipios')) {
        await Hive.openBox('catalog_municipios');
      }
      final catalogBox = Hive.box('catalog_municipios');

      if (catalogBox.isNotEmpty) {
        // ¡Hay datos locales! Entra en modo offline.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Modo Offline: No se pudo verificar la sesión.'),
              backgroundColor: Colors.blueGrey,
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProductoresPage()),
          );
        }
      } else {
        // No hay sesión online Y no hay datos locales. Forzar login.
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthPage()),
          );
        }
      }
    } catch (e) {
      // Si todo falla, ir a la página de login por seguridad.
      debugPrint("Error en _redirect, redirigiendo a AuthPage: $e");
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Una pantalla de carga simple
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
