import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'productores_page.dart';

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

  // Colores consistentes con la app
  final Color natureGreen = const Color(0xFF6DB571);
  final Color backgroundNature = const Color(0xFFEAFBE7);
  final Color accentNature = const Color(0xFFB2D8B2);

  // Reemplaza únicamente el método _authenticate en AuthPage por lo siguiente:

  Future<void> _authenticate() async {
    setState(() {
      _isLoading = true;
      errorMsg = '';
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final supabase = Supabase.instance.client;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMsg = 'Email y contraseña son obligatorios';
        _isLoading = false;
      });
      return;
    }

    try {
      debugPrint('Attempting signInWithPassword for: $email');
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // Log completo de la respuesta para debug
      debugPrint('Supabase auth response: $response');
      try {
        // algunas versiones exponen session/user/error en distintos campos
        debugPrint('response.session: ${response.session}');
        debugPrint('response.user: ${response.user}');
        // response.error puede ser null o no existir según versión; comprobamos con try
        final err = (response as dynamic).error;
        if (err != null) debugPrint('response.error: ${err}');
      } catch (e) {
        debugPrint('No se pudo inspeccionar response internamente: $e');
      }

      if ((response.session != null) || (response.user != null)) {
        _emailController.clear();
        _passwordController.clear();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProductoresPage()),
          );
        }
      } else {
        setState(() {
          errorMsg =
              'Error en el inicio de sesión (sin session/user). Revisa logs.';
        });
        debugPrint('Login no produjo session/user. Response: $response');
      }
    } catch (e, st) {
      // CAPTURAMOS TODO y mostramos el mensaje y stacktrace en consola
      debugPrint('Exception during signIn: $e');
      debugPrint('Stacktrace: $st');
      setState(() {
        errorMsg = 'Error al iniciar sesión: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                        const SizedBox(height: 10),
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
                            // Puedes implementar recuperación de contraseña aquí
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
                // Pie discreto: opción de registro oculta por petición del usuario
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

extension on AuthResponse {
  get error => null;
}
