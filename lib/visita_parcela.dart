import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'historial_visitas_parcela.dart';

class FormularioVisita extends StatefulWidget {
  // Recibe el ID de la parcela a la que pertenece esta visita.
  final String parcelaId;

  const FormularioVisita({super.key, required this.parcelaId});

  @override
  State<FormularioVisita> createState() => _FormularioVisitaState();
}

class _FormularioVisitaState extends State<FormularioVisita> {
  final _formKey = GlobalKey<FormState>();
  // Controladores principales
  final _observacionesController = TextEditingController();
  final _recomendacionesController = TextEditingController();

  // Controladores de conteo general
  final _EPCController = TextEditingController();
  final _APCController = TextEditingController();
  final _MPCController = TextEditingController();
  final _BPCController = TextEditingController();
  final _CPCController = TextEditingController();

  // Controladores para la tabla de monitoreo (5 plantas)
  final List<TextEditingController> _tallosControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _ejesControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _floresControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _frutosSinDanoControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _frutosConPicudoControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _frutosConTripsControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _frutosConMoscaControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _frutosSinCosecharControllers =
      List.generate(5, (_) => TextEditingController());

  // Estado para manejar la fecha seleccionada.
  DateTime? _selectedDate;
  bool _isLoading = false;

  final DateFormat _displayFormat = DateFormat('dd/MM/yyyy');

  @override
  void dispose() {
    // Limpia todos los controladores
    _observacionesController.dispose();
    _recomendacionesController.dispose();
    _EPCController.dispose();
    _APCController.dispose();
    _MPCController.dispose();
    _BPCController.dispose();
    _CPCController.dispose();
    for (var i = 0; i < 5; i++) {
      _tallosControllers[i].dispose();
      _ejesControllers[i].dispose();
      _floresControllers[i].dispose();
      _frutosSinDanoControllers[i].dispose();
      _frutosConPicudoControllers[i].dispose();
      _frutosConTripsControllers[i].dispose();
      _frutosConMoscaControllers[i].dispose();
      _frutosSinCosecharControllers[i].dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        // Aplicar tema consistente al DatePicker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF6DB571), // header background
              onPrimary: Colors.white, // header text
              onSurface: Colors.black, // body text
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6DB571),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Guarda la visita en Supabase — sin usar operadores '!' inseguros
  /// y con manejo seguro de userMetadata.
  Future<void> _guardarVisita() async {
    // Evitar usar currentState! — comprobar nulo de forma segura.
    final formState = _formKey.currentState;
    if (formState == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Formulario no disponible. Intenta de nuevo.'),
          ),
        );
      }
      return;
    }

    final valid = formState.validate();
    if (!valid) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una fecha')),
      );
      return;
    }

    // Obtener usuario actual de Supabase
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: usuario no identificado.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Obtener email con fallback seguro
      final String userId = user.id ?? '';
      String userEmail = user.email ?? '';

      final meta = user.userMetadata;
      if ((userEmail == null || userEmail.isEmpty) && meta != null) {
        // Si meta es un Map<String, dynamic>, usarlo de forma segura
        if (meta is Map<String, dynamic>) {
          // Intentar varias claves comunes para email
          final dynamic candidate =
              meta['email'] ??
              meta['email_address'] ??
              meta['emailAddress'] ??
              meta['user_email'];
          if (candidate != null) userEmail = candidate.toString();
        } else {
          // meta no es Map, intentar acceso null-aware por seguridad (último recurso)
          try {
            final dynamic candidate = (meta as dynamic)?['email'];
            if (candidate != null) userEmail = candidate.toString();
          } catch (_) {
            // ignorar
          }
        }
      }
      userEmail = userEmail ?? '';

      // Preparar monitoreo_plantas
      List<Map<String, int>> monitoreoPlantas = [];
      for (var i = 0; i < 5; i++) {
        monitoreoPlantas.add({
          'planta': i + 1,
          'tallos_florales': int.tryParse(_tallosControllers[i].text) ?? 0,
          'eje_floral': int.tryParse(_ejesControllers[i].text) ?? 0,
          'flores': int.tryParse(_floresControllers[i].text) ?? 0,
          'frutos_sin_dano':
              int.tryParse(_frutosSinDanoControllers[i].text) ?? 0,
          'frutos_con_picudo':
              int.tryParse(_frutosConPicudoControllers[i].text) ?? 0,
          'frutos_con_trips':
              int.tryParse(_frutosConTripsControllers[i].text) ?? 0,
          'frutos_con_mosca':
              int.tryParse(_frutosConMoscaControllers[i].text) ?? 0,
          'frutos_sin_cosechar':
              int.tryParse(_frutosSinCosecharControllers[i].text) ?? 0,
        });
      }

      final supabase = Supabase.instance.client;

      // Convertir parcelaId si es posible a int
      dynamic parcelaIdToSave = widget.parcelaId;
      final parsed = int.tryParse(widget.parcelaId);
      if (parsed != null) parcelaIdToSave = parsed;

      final insertData = {
        'id_parcela': parcelaIdToSave,
        'fecha_visita': _selectedDate!.toIso8601String(),
        'observaciones': _observacionesController.text,
        'recomendaciones': _recomendacionesController.text,
        'fecha_registro': DateTime.now().toIso8601String(),
        'ep': int.tryParse(_EPCController.text) ?? 0,
        'ap': int.tryParse(_APCController.text) ?? 0,
        'mp': int.tryParse(_MPCController.text) ?? 0,
        'bp': int.tryParse(_BPCController.text) ?? 0,
        'cp': int.tryParse(_CPCController.text) ?? 0,
        'monitoreo_plantas': monitoreoPlantas,
        'usuario_registro_email': userEmail,
        'usuario_registro_id': userId,
      };

      // Insertar en la tabla (await la petición). No usamos .execute().
      await supabase.from('visitas_monitoreo').insert(insertData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visita registrada con éxito')),
        );
        Navigator.pop(
          context,
          true,
        ); // devuelve true para que la pantalla anterior refresque
      }
    } catch (e, st) {
      debugPrint('Error guardando visita: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar la visita: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildCounterField(TextEditingController controller, String label) {
    return Expanded(
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: InputBorder.none,
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            validator: (_) => null, // permitir campos vacíos
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(TextEditingController controller) {
    return SizedBox(
      width: 80,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  DataRow _buildTableRow(
    String label,
    List<TextEditingController> controllers,
  ) {
    return DataRow(
      cells: [
        DataCell(Text(label)),
        DataCell(_buildTableCell(controllers[0])),
        DataCell(_buildTableCell(controllers[1])),
        DataCell(_buildTableCell(controllers[2])),
        DataCell(_buildTableCell(controllers[3])),
        DataCell(_buildTableCell(controllers[4])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final natureGreen = const Color(0xFF6DB571);
    final backgroundNature = const Color(0xFFEAFBE7);
    final accentNature = const Color(0xFFB2D8B2);

    final formattedDate = _selectedDate == null
        ? 'Seleccionar fecha'
        : _displayFormat.format(_selectedDate!);

    return Scaffold(
      backgroundColor: backgroundNature,
      appBar: AppBar(
        backgroundColor: natureGreen,
        elevation: 0,
        title: Text(
          'Registrar Visita',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Ver Historial',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HistorialVisitasParcela(parcelaId: widget.parcelaId),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabecera con imagen
                      Center(
                        child: CircleAvatar(
                          radius: 52,
                          backgroundImage: const AssetImage(
                            'assets/images/field.png',
                          ),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Fecha
                      Card(
                        color: accentNature,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fecha de visita',
                                      style: GoogleFonts.montserrat(
                                        color: natureGreen,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formattedDate,
                                      style: GoogleFonts.montserrat(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _selectDate(context),
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                ),
                                label: Text(
                                  'Seleccionar',
                                  style: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: natureGreen,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Conteo General
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Conteo General',
                                style: GoogleFonts.montserrat(
                                  color: natureGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _buildCounterField(_EPCController, 'EP'),
                                  _buildCounterField(_APCController, 'AP'),
                                  _buildCounterField(_MPCController, 'MP'),
                                  _buildCounterField(_BPCController, 'BP'),
                                  _buildCounterField(_CPCController, 'CP'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Monitoreo de Plantas
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monitoreo de Plantas',
                                style: GoogleFonts.montserrat(
                                  color: natureGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 16,
                                  headingTextStyle: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('Situación')),
                                    DataColumn(label: Text('EP')),
                                    DataColumn(label: Text('AP')),
                                    DataColumn(label: Text('MP')),
                                    DataColumn(label: Text('BP')),
                                    DataColumn(label: Text('CP')),
                                  ],
                                  rows: [
                                    _buildTableRow(
                                      "Tallos Florales",
                                      _tallosControllers,
                                    ),
                                    _buildTableRow(
                                      "Eje Floral",
                                      _ejesControllers,
                                    ),
                                    _buildTableRow(
                                      "Flores",
                                      _floresControllers,
                                    ),
                                    _buildTableRow(
                                      "Frutos s/Daño",
                                      _frutosSinDanoControllers,
                                    ),
                                    _buildTableRow(
                                      "Frutos c/Picudo",
                                      _frutosConPicudoControllers,
                                    ),
                                    _buildTableRow(
                                      "Frutos c/Trips",
                                      _frutosConTripsControllers,
                                    ),
                                    _buildTableRow(
                                      "Frutos c/Mosca",
                                      _frutosConMoscaControllers,
                                    ),
                                    _buildTableRow(
                                      "Frutos s/Cosechar",
                                      _frutosSinCosecharControllers,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Observaciones y Recomendaciones
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Observaciones',
                                style: GoogleFonts.montserrat(
                                  color: natureGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _observacionesController,
                                decoration: InputDecoration(
                                  hintText: 'Escribe las observaciones...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                maxLines: 4,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Ingresa las observaciones';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Recomendaciones',
                                style: GoogleFonts.montserrat(
                                  color: natureGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _recomendacionesController,
                                decoration: InputDecoration(
                                  hintText: 'Sugerir acciones...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Botones finales
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _guardarVisita,
                              icon: const Icon(Icons.save),
                              label: Text(
                                'Guardar Visita',
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: natureGreen,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const Icon(Icons.cancel),
                              label: Text(
                                'Cancelar',
                                style: GoogleFonts.montserrat(),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: BorderSide(color: Colors.red.shade400),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
