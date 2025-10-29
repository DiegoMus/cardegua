import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

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
  bool _rememberOffline = true;

  final Color natureGreen = const Color(0xFF6DB571);
  final Color backgroundNature = const Color(0xFFEAFBE7);
  final Color accentNature = const Color(0xFFB2D8B2);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _generateSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPassword(String salt, String password) {
    final bytes = utf8.encode(salt + password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveLocalCredentials(String email, String password) async {
    final emailKey = 'auth_$email';
    final salt = _generateSalt(16);
    final hash = _hashPassword(salt, password);
    final payload = jsonEncode({'salt': salt, 'hash': hash, 'email': email});
    await _secureStorage.write(key: emailKey, value: payload);
  }

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
    return int.tryParse(v.toString());
  }

  double? _toNullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  // EN lib/auth_page.dart

  Future<void> _initialFullSync() async {
    // --- Preparación (abrir cajas, etc.) ---
    try {
      if (!Hive.isAdapterRegistered(ProductorAdapter().typeId))
        Hive.registerAdapter(ProductorAdapter());
      if (!Hive.isAdapterRegistered(ParcelaAdapter().typeId))
        Hive.registerAdapter(ParcelaAdapter());
    } catch (_) {}

    await Future.wait([
      if (!Hive.isBoxOpen('productores'))
        Hive.openBox<Productor>('productores'),
      if (!Hive.isBoxOpen('parcelas')) Hive.openBox<Parcela>('parcelas'),
      if (!Hive.isBoxOpen('catalog_tipo_cultivo'))
        Hive.openBox('catalog_tipo_cultivo'),
      if (!Hive.isBoxOpen('catalog_municipios'))
        Hive.openBox('catalog_municipios'),
    ]);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Sincronizando datos...'),
            ],
          ),
        ),
      );
    }

    final supabase = Supabase.instance.client;
    final productorBox = Hive.box<Productor>('productores');
    final parcelaBox = Hive.box<Parcela>('parcelas');

    try {
      // --- LÓGICA DE "UPSERT" INTELIGENTE PARA PRODUCTORES ---
      final remoteProductores = await supabase.from('productores').select();

      // Mapea los productores locales por UUID y serverId para búsquedas rápidas
      final localProdsByUuid = {for (var p in productorBox.values) p.uuid: p};
      final localProdsByServerId = {
        for (var p in productorBox.values.where((p) => p.serverId != null))
          p.serverId!: p,
      };

      for (final remoteData in remoteProductores) {
        final serverId = _toNullableInt(remoteData['id_productor']);
        final uuid = remoteData['uuid'] as String?;
        if (serverId == null || uuid == null) continue;

        Productor? existingLocal;
        // Prioridad 1: Buscar por UUID. Es la fuente de verdad.
        if (localProdsByUuid.containsKey(uuid)) {
          existingLocal = localProdsByUuid[uuid];
        }
        // Prioridad 2: Buscar por serverId (para compatibilidad o casos borde).
        else if (localProdsByServerId.containsKey(serverId)) {
          existingLocal = localProdsByServerId[serverId];
        }

        // Crea el objeto actualizado con los datos del servidor.
        final updatedProductor = Productor(
          serverId: serverId,
          uuid: uuid, // Usa siempre el UUID del servidor.
          nombre: remoteData['nombre'] ?? '',
          email: remoteData['email'],
          telefono: remoteData['telefono'],
          cui: remoteData['cui'],
          status: 'synced',
          operation: null,
        );

        if (existingLocal != null) {
          // Si encontramos un registro local, lo ACTUALIZAMOS en su misma clave.
          // Esto preserva el `key` de Hive y evita duplicados.
          await productorBox.put(existingLocal.key, updatedProductor);
        } else {
          // Si no existe de ninguna manera, lo añadimos como nuevo.
          await productorBox.add(updatedProductor);
        }
      }

      // --- LÓGICA SIMILAR PARA PARCELAS ---
      // (Puedes aplicar el mismo patrón de "upsert" inteligente para las parcelas si lo necesitas)

      // Sincronizar Catálogos
      await _syncCatalog(
        supabase,
        'tipo_cultivo',
        'id',
        Hive.box('catalog_tipo_cultivo'),
      );
      await _syncCatalog(
        supabase,
        'municipios',
        'id_municipio',
        Hive.box('catalog_municipios'),
      );

      debugPrint('Initial full sync finished.');
    } catch (e) {
      debugPrint('Error en _initialFullSync: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error durante la sincronización: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _syncCatalog(
    SupabaseClient client,
    String table,
    String idCol,
    Box box,
  ) async {
    try {
      final data = await client.from(table).select();
      await box.clear();
      for (final row in data) {
        final id = row[idCol]?.toString();
        if (id != null) {
          await box.put(id, Map<String, dynamic>.from(row));
        }
      }
    } catch (e) {
      debugPrint('Error sincronizando catálogo $table: $e');
    }
  }

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

    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline =
        connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);

    if (isOnline) {
      try {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.session != null) {
          if (_rememberOffline) {
            await _saveLocalCredentials(email, password);
          }
          await _initialFullSync();
          if (mounted)
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProductoresPage()),
            );
          return;
        }
      } on AuthException catch (e) {
        setState(() {
          errorMsg = 'Credenciales incorrectas: ${e.message}';
          _isLoading = false;
        });
        return;
      } catch (e) {
        debugPrint('Error inesperado en login online: $e');
      }
    }

    final localSuccess = await _verifyLocalCredentials(email, password);
    if (localSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modo Offline: Usando datos guardados.'),
            backgroundColor: Colors.blueGrey,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProductoresPage()),
        );
      }
    } else {
      setState(() {
        errorMsg = isOnline
            ? 'Credenciales incorrectas.'
            : 'Sin conexión y las credenciales no coinciden.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // La UI no necesita cambios, se mantiene la que ya tenías.
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
                          'Ingresa con tu correo y contraseña',
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
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _rememberOffline,
                          onChanged: (v) =>
                              setState(() => _rememberOffline = v ?? false),
                          title: Text(
                            'Permitir inicio offline',
                            style: GoogleFonts.montserrat(fontSize: 13),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: natureGreen,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (errorMsg.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                      ],
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
}
