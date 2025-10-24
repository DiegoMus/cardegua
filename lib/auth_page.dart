// lib/auth_page.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'productores_page.dart';
import 'parcelas_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String errorMsg = '';
  bool _rememberOffline = true; // por defecto permitir cachear credenciales

  // Colores consistentes con la app
  final Color natureGreen = const Color(0xFF6DB571);
  final Color backgroundNature = const Color(0xFFEAFBE7);
  final Color accentNature = const Color(0xFFB2D8B2);

  // Secure storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Genera salt seguro
  String _generateSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  // Crea hash SHA256(salt + password)
  String _hashPassword(String salt, String password) {
    final bytes = utf8.encode(salt + password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Guarda credenciales hashed en secure storage
  Future<void> _saveLocalCredentials(String email, String password) async {
    final emailKey = 'auth_$email';
    final salt = _generateSalt(16);
    final hash = _hashPassword(salt, password);
    final payload = jsonEncode({'salt': salt, 'hash': hash, 'email': email});
    await _secureStorage.write(key: emailKey, value: payload);
  }

  // Verifica credenciales locales
  Future<bool> _verifyLocalCredentials(String email, String password) async {
    final emailKey = 'auth_$email';
    final stored = await _secureStorage.read(key: emailKey);
    if (stored == null) return false;
    try {
      final Map<String, dynamic> obj = jsonDecode(stored);
      final salt = obj['salt'] as String?;
      final hash = obj['hash'] as String?;
      if (salt == null || hash == null) return false;
      final attempt = _hashPassword(salt, password);
      // comparación en tiempo constante
      return _constantTimeEquals(attempt, hash);
    } catch (_) {
      return false;
    }
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var res = 0;
    for (var i = 0; i < a.length; i++) {
      res |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return res == 0;
  }

  int? _toNullableInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    return int.tryParse(s);
  }

  double? _toNullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return (v as num).toDouble();
    final s = v.toString().replaceAll(',', '.');
    return double.tryParse(s);
  }

  // ---------------------------
  // Inicial full sync
  // ---------------------------
  Future<void> _initialFullSync() async {
    // Registrar adapters si aún no se han registrado (safe)
    try {
      if (!Hive.isAdapterRegistered(ProductorAdapter().typeId)) {
        Hive.registerAdapter(ProductorAdapter());
      }
    } catch (_) {}
    try {
      if (!Hive.isAdapterRegistered(ParcelaAdapter().typeId)) {
        Hive.registerAdapter(ParcelaAdapter());
      }
    } catch (_) {}

    // Abrir boxes si no están abiertas
    if (!Hive.isBoxOpen('productores')) {
      await Hive.openBox<Productor>('productores');
    }
    if (!Hive.isBoxOpen('parcelas')) {
      await Hive.openBox<Parcela>('parcelas');
    }
    if (!Hive.isBoxOpen('catalog_tipo_cultivo')) {
      await Hive.openBox('catalog_tipo_cultivo');
    }
    if (!Hive.isBoxOpen('catalog_municipios')) {
      await Hive.openBox('catalog_municipios');
    }
    if (!Hive.isBoxOpen('catalog_departamentos')) {
      await Hive.openBox('catalog_departamentos');
    }

    final supabase = Supabase.instance.client;
    final Box<Productor> productorBox = Hive.box<Productor>('productores');
    final Box<Parcela> parcelaBox = Hive.box<Parcela>('parcelas');
    final Box tipoBox = Hive.box('catalog_tipo_cultivo');
    final Box muniBox = Hive.box('catalog_municipios');
    final Box depsBox = Hive.box('catalog_departamentos');

    // Descargar productores (upsert local)
    try {
      final prodRes = await supabase.from('productores').select();
      final List<dynamic> prodList = (prodRes is List) ? prodRes : [];
      for (final r in prodList) {
        if (r is! Map) continue;
        final rawId = r['id_productor'] ?? r['id'];
        final int? sid = _toNullableInt(rawId);
        if (sid == null) continue;

        // buscar local por serverId
        Productor existing;
        try {
          existing = productorBox.values.firstWhere((p) => p.serverId == sid);
        } catch (_) {
          existing = Productor(nombre: (r['nombre'] ?? '').toString());
        }

        existing.serverId = sid;
        existing.nombre = (r['nombre'] ?? existing.nombre).toString();
        existing.email = (r['email'] ?? existing.email)?.toString();
        existing.telefono = (r['telefono'] ?? existing.telefono)?.toString();
        existing.cui = (r['cui'] ?? existing.cui)?.toString();
        existing.operation = null;
        existing.status = 'synced';
        existing.updatedAt = DateTime.now().toIso8601String();

        if (existing.key != null) {
          await existing.save();
        } else {
          await productorBox.add(existing);
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando productores en initialFullSync: $e');
      debugPrint('$st');
    }

    // Descargar parcelas (upsert local)
    try {
      final parcRes = await supabase.from('parcelas').select();
      final List<dynamic> parcList = (parcRes is List) ? parcRes : [];
      for (final r in parcList) {
        if (r is! Map) continue;
        final rawId = r['id_parcela'] ?? r['id'];
        final int? sid = _toNullableInt(rawId);
        if (sid == null) continue;

        Parcela existing;
        try {
          existing = parcelaBox.values.firstWhere((p) => p.serverId == sid);
        } catch (_) {
          existing = Parcela(nombre: (r['nombre'] ?? '').toString());
        }

        existing.serverId = sid;
        existing.nombre = (r['nombre'] ?? existing.nombre).toString();
        existing.area = _toNullableDouble(r['area']);
        existing.tipoCultivoNombre = (r['tipo_cultivo'] ?? r['cultivo'])
            ?.toString();
        existing.idTipoCultivo = _toNullableInt(r['id_tipo_cultivo']);
        existing.latitud = _toNullableDouble(r['latitud']);
        existing.longitud = _toNullableDouble(r['longitud']);
        existing.altitud = _toNullableDouble(r['altitud']);
        existing.idMunicipio = _toNullableInt(r['id_municipio']);
        existing.vigente = r['vigente'] == null
            ? true
            : (r['vigente'] as bool? ?? true);
        existing.fechaRegistroIso = r['fecha_registro']?.toString();
        // asignar productorId (si el servidor lo incluye)
        existing.productorId = _toNullableInt(
          r['id_productor'] ?? r['id_productor'],
        );
        existing.operation = null;
        existing.status = 'synced';
        existing.updatedAt = DateTime.now().toIso8601String();

        if (existing.key != null) {
          await existing.save();
        } else {
          await parcelaBox.add(existing);
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando parcelas en initialFullSync: $e');
      debugPrint('$st');
    }

    // Catálogos
    try {
      final resTipo = await supabase.from('tipo_cultivo').select();
      if (resTipo is List) {
        await tipoBox.clear();
        for (final e in resTipo) {
          if (e is Map) {
            final id = e['id'] ?? e['id_tipo'] ?? e['id_cultivo'];
            if (id != null)
              tipoBox.put(id.toString(), Map<String, dynamic>.from(e));
          }
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando tipo_cultivo: $e');
      debugPrint('$st');
    }

    try {
      final resDeps = await supabase.from('departamentos').select();
      if (resDeps is List) {
        await depsBox.clear();
        for (final e in resDeps) {
          if (e is Map) {
            final id = e['id'] ?? e['id_departamento'];
            if (id != null)
              depsBox.put(id.toString(), Map<String, dynamic>.from(e));
          }
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando departamentos: $e');
      debugPrint('$st');
    }

    try {
      final resMun = await supabase.from('municipios').select();
      if (resMun is List) {
        await muniBox.clear();
        for (final e in resMun) {
          if (e is Map) {
            final id = e['id_municipio'] ?? e['id'];
            if (id != null)
              muniBox.put(id.toString(), Map<String, dynamic>.from(e));
          }
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando municipios: $e');
      debugPrint('$st');
    }

    // Verificación / logs después de la sync inicial
    try {
      final Box<Productor> checkProdBox = Hive.box<Productor>('productores');
      debugPrint(
        'DEBUG: productores guardados localmente = ${checkProdBox.length}',
      );
      for (final p in checkProdBox.values) {
        debugPrint(
          'DEBUG: productor local -> key=${p.key} serverId=${p.serverId} nombre=${p.nombre} status=${p.status} operation=${p.operation}',
        );
      }

      final Box<Parcela> checkParBox = Hive.box<Parcela>('parcelas');
      debugPrint(
        'DEBUG: parcelas guardadas localmente = ${checkParBox.length}',
      );
      for (final p in checkParBox.values) {
        debugPrint(
          'DEBUG: parcela local -> key=${p.key} serverId=${p.serverId} nombre=${p.nombre} status=${p.status} productorId=${p.productorId}',
        );
      }

      // Mostrar al usuario cuántos productores se guardaron
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sincronización completa: ${checkProdBox.length} productores guardados localmente.',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('DEBUG: Error comprobando boxes tras sync: $e');
      debugPrint('$st');
    }

    debugPrint('Initial full sync finished.');
  }

  // ---------------------------
  // AUTENTICACIÓN
  // ---------------------------
  Future<void> _authenticate() async {
    setState(() {
      _isLoading = true;
      errorMsg = '';
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMsg = 'Email y contraseña son obligatorios';
        _isLoading = false;
      });
      return;
    }

    // Comprobar conectividad
    final connectivity = await Connectivity().checkConnectivity();
    final online = connectivity != ConnectivityResult.none;

    if (online) {
      // Intentar autenticación online con Supabase
      final supabase = Supabase.instance.client;
      try {
        debugPrint('Intentando inicio de sesión online para $email');
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        debugPrint('Supabase auth response: $response');

        if ((response.session != null) || (response.user != null)) {
          // Guardar credenciales localmente si el usuario pidió permitir inicio offline
          if (_rememberOffline) {
            try {
              await _saveLocalCredentials(email, password);
            } catch (e) {
              debugPrint('No se pudo guardar credenciales localmente: $e');
            }
          }

          // Ejecutar initial full sync para cachear datos necesarios offline
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => WillPopScope(
                onWillPop: () async => false,
                child: AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Sincronizando datos iniciales...'),
                    ],
                  ),
                ),
              ),
            );
          }

          try {
            await _initialFullSync();
          } catch (e, st) {
            debugPrint('Error en initialFullSync: $e');
            debugPrint('$st');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No se completó la sincronización inicial. Algunos datos pueden faltar.',
                  ),
                ),
              );
            }
          } finally {
            if (mounted) Navigator.of(context, rootNavigator: true).pop();
          }

          _emailController.clear();
          _passwordController.clear();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProductoresPage()),
            );
          }
        } else {
          // fallback a login local si existe
          final localOk = await _verifyLocalCredentials(email, password);
          // fallback local (dentro de _authenticate cuando localOk == true)
          if (localOk) {
            // asegurarnos de que Hive y adapters están listos y boxes abiertas
            try {
              if (!Hive.isAdapterRegistered(ProductorAdapter().typeId)) {
                Hive.registerAdapter(ProductorAdapter());
              }
            } catch (_) {}
            try {
              if (!Hive.isAdapterRegistered(ParcelaAdapter().typeId)) {
                Hive.registerAdapter(ParcelaAdapter());
              }
            } catch (_) {}

            if (!Hive.isBoxOpen('productores'))
              await Hive.openBox('productores');
            if (!Hive.isBoxOpen('parcelas')) await Hive.openBox('parcelas');

            // Esperar a que ProductoresPage cargue locales
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProductoresPage()),
            );
          } else {
            setState(() {
              errorMsg =
                  'Credenciales inválidas (online). Revisa correo/contraseña.';
            });
          }
        }
      } catch (e, st) {
        debugPrint('Exception during signIn online: $e');
        debugPrint('Stacktrace: $st');

        // fallback local
        final localOk = await _verifyLocalCredentials(email, password);
        if (localOk) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Inicio local (offline) usando credenciales guardadas.',
                ),
              ),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProductoresPage()),
            );
          }
        } else {
          setState(() {
            errorMsg = 'Error al iniciar sesión: ${e.toString()}';
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      // Sin conexión: intentar login local
      final ok = await _verifyLocalCredentials(email, password);
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Inicio local (offline) correcto.')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProductoresPage()),
          );
        }
      } else {
        setState(() {
          errorMsg =
              'Sin conexión y no hay credenciales guardadas para este usuario. Conéctate a internet para autenticar.';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType ?? TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: natureGreen),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
      style: GoogleFonts.montserrat(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundNature,
      appBar: AppBar(
        backgroundColor: natureGreen,
        elevation: 0,
        title: Text(
          'Iniciar Sesión',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera / Logo
                Center(
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: Colors.transparent,
                    backgroundImage: const AssetImage(
                      'assets/images/jardineria.png',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: accentNature,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Bienvenido',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            color: natureGreen,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ingresa con tu correo y contraseña para continuar',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Contraseña',
                          icon: Icons.lock,
                          obscure: _obscurePassword,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: natureGreen,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _rememberOffline,
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _rememberOffline = v);
                          },
                          title: Text(
                            'Permitir inicio offline (guardar credenciales localmente)',
                            style: GoogleFonts.montserrat(fontSize: 13),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: natureGreen,
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 6),
                        if (errorMsg.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              errorMsg,
                              style: GoogleFonts.montserrat(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 6),
                        _isLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: natureGreen,
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _authenticate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: natureGreen,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Iniciar Sesión',
                                  style: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Función de recuperar contraseña no implementada',
                                ),
                              ),
                            );
                          },
                          child: Text(
                            '¿Olvidaste tu contraseña?',
                            style: GoogleFonts.montserrat(color: natureGreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Contacto administrador para crear cuentas',
                    style: GoogleFonts.montserrat(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
