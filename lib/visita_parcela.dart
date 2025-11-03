import 'dart:async';
import 'dart:convert';
import 'package:cardegua/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'historial_visitas_parcela.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

@HiveType(typeId: 20) // ¡Asegúrate de que este typeId no esté en uso!
class VisitaMonitoreo extends HiveObject {
  @HiveField(0)
  int? serverId;
  @HiveField(1)
  String uuid;
  @HiveField(2)
  String parcelaUuid;
  @HiveField(3)
  int? parcelaId;
  @HiveField(4)
  String fechaVisita;
  @HiveField(5)
  String? observaciones;
  @HiveField(6)
  String? recomendaciones;
  @HiveField(7)
  int? ep;
  @HiveField(8)
  int? ap;
  @HiveField(9)
  int? mp;
  @HiveField(10)
  int? bp;
  @HiveField(11)
  int? cp;
  @HiveField(12)
  String monitoreoPlantasJson; // Guardamos el JSON como String
  @HiveField(13)
  String? usuarioRegistroEmail;
  @HiveField(14)
  String? usuarioRegistroId;
  @HiveField(15)
  String status;
  @HiveField(16)
  String? operation;
  @HiveField(17)
  String updatedAt;

  VisitaMonitoreo({
    this.serverId,
    String? uuid,
    required this.parcelaUuid,
    this.parcelaId,
    required this.fechaVisita,
    this.observaciones,
    this.recomendaciones,
    this.ep,
    this.ap,
    this.mp,
    this.bp,
    this.cp,
    required this.monitoreoPlantasJson,
    this.usuarioRegistroEmail,
    this.usuarioRegistroId,
    this.status = 'pending',
    this.operation,
    String? updatedAt,
  }) : this.uuid = uuid ?? const Uuid().v4(),
       this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  // Dentro de la clase VisitaMonitoreo
  // En lib/visita_parcela.dart, dentro de la clase VisitaMonitoreo

  factory VisitaMonitoreo.fromJson(Map<String, dynamic> json) {
    return VisitaMonitoreo(
      serverId: json['id_visita'] as int?,
      uuid: json['uuid'] as String? ?? '', // <-- CORRECCIÓN
      parcelaUuid: json['uuid_parcelas'] as String? ?? '', // <-- CORRECCIÓN
      parcelaId: json['id_parcela'] as int?,
      fechaVisita: json['fecha_visita'] as String? ?? '', // <-- CORRECCIÓN
      observaciones: json['observaciones'] as String?,
      recomendaciones: json['recomendaciones'] as String?,
      ep: json['ep'] as int?,
      ap: json['ap'] as int?,
      mp: json['mp'] as int?,
      bp: json['bp'] as int?,
      cp: json['cp'] as int?,
      monitoreoPlantasJson: jsonEncode(json['monitoreo_plantas'] ?? []),
      usuarioRegistroId: json['usuario_registro_id'] as String?,
      usuarioRegistroEmail: json['usuario_registro_email'] as String?,
      status: 'synced',
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'uuid_parcelas': parcelaUuid,
      'id_parcela': parcelaId,
      'fecha_visita': fechaVisita,
      'observaciones': observaciones,
      'recomendaciones': recomendaciones,
      'ep': ep,
      'ap': ap,
      'mp': mp,
      'bp': bp,
      'cp': cp,
      'monitoreo_plantas': jsonDecode(monitoreoPlantasJson),
      'usuario_registro_id': usuarioRegistroId,
      'usuario_registro_email': usuarioRegistroEmail,
    };
  }
}

class VisitaMonitoreoAdapter extends TypeAdapter<VisitaMonitoreo> {
  @override
  final int typeId = 20;

  @override
  VisitaMonitoreo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VisitaMonitoreo(
      serverId: fields[0] as int?,
      uuid: fields[1] as String,
      parcelaUuid: fields[2] as String,
      parcelaId: fields[3] as int?,
      fechaVisita: fields[4] as String,
      observaciones: fields[5] as String?,
      recomendaciones: fields[6] as String?,
      ep: fields[7] as int?,
      ap: fields[8] as int?,
      mp: fields[9] as int?,
      bp: fields[10] as int?,
      cp: fields[11] as int?,
      monitoreoPlantasJson: fields[12] as String,
      usuarioRegistroEmail: fields[13] as String?,
      usuarioRegistroId: fields[14] as String?,
      status: fields[15] as String? ?? 'pending',
      operation: fields[16] as String?,
      updatedAt: fields[17] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, VisitaMonitoreo obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.serverId)
      ..writeByte(1)
      ..write(obj.uuid)
      ..writeByte(2)
      ..write(obj.parcelaUuid)
      ..writeByte(3)
      ..write(obj.parcelaId)
      ..writeByte(4)
      ..write(obj.fechaVisita)
      ..writeByte(5)
      ..write(obj.observaciones)
      ..writeByte(6)
      ..write(obj.recomendaciones)
      ..writeByte(7)
      ..write(obj.ep)
      ..writeByte(8)
      ..write(obj.ap)
      ..writeByte(9)
      ..write(obj.mp)
      ..writeByte(10)
      ..write(obj.bp)
      ..writeByte(11)
      ..write(obj.cp)
      ..writeByte(12)
      ..write(obj.monitoreoPlantasJson)
      ..writeByte(13)
      ..write(obj.usuarioRegistroEmail)
      ..writeByte(14)
      ..write(obj.usuarioRegistroId)
      ..writeByte(15)
      ..write(obj.status)
      ..writeByte(16)
      ..write(obj.operation)
      ..writeByte(17)
      ..write(obj.updatedAt);
  }
}

class FormularioVisita extends StatefulWidget {
  // Recibe el ID de la parcela a la que pertenece esta visita.
  //final String parcelaId;
  final String parcelaUuid;

  const FormularioVisita({super.key, required this.parcelaUuid});

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

  final List<TextEditingController> _frutosSinCosecharControllers =
      List.generate(5, (_) => TextEditingController());

  // Estado para manejar la fecha seleccionada.
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isOnline = false;

  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  final DateFormat _displayFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    // Inicializar el estado de conectividad
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final conn = Connectivity();
    final initialResult = await conn.checkConnectivity();
    _isOnline =
        initialResult.contains(ConnectivityResult.mobile) ||
        initialResult.contains(ConnectivityResult.wifi);
    setState(() {});
    _connectivitySub = conn.onConnectivityChanged.listen((result) {
      final newStatus =
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.wifi);
      if (_isOnline != newStatus) {
        setState(() {
          _isOnline = newStatus;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
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
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una fecha')),
      );
      return;
    }

    if (_isOnline) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Guardando visita...'),
            ],
          ),
        ),
      );
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;

      List<Map<String, int>> monitoreoPlantas = List.generate(
        5,
        (i) => {
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
          'frutos_sin_cosechar':
              int.tryParse(_frutosSinCosecharControllers[i].text) ?? 0,
        },
      );
      final monitoreoJson = jsonEncode(monitoreoPlantas);

      // 1. Crear el objeto VisitaMonitoreo para Hive
      final nuevaVisita = VisitaMonitoreo(
        parcelaUuid: widget.parcelaUuid,
        fechaVisita: _selectedDate!.toIso8601String(),
        observaciones: _observacionesController.text,
        recomendaciones: _recomendacionesController.text,
        ep: int.tryParse(_EPCController.text),
        ap: int.tryParse(_APCController.text),
        mp: int.tryParse(_MPCController.text),
        bp: int.tryParse(_BPCController.text),
        cp: int.tryParse(_CPCController.text),
        monitoreoPlantasJson: monitoreoJson,
        usuarioRegistroId: user?.id,
        usuarioRegistroEmail: user?.email,
        status: 'pending',
        operation: 'create',
      );

      // 2. Registrar el adapter y guardar en la caja de Hive
      try {
        if (!Hive.isAdapterRegistered(VisitaMonitoreoAdapter().typeId)) {
          Hive.registerAdapter(VisitaMonitoreoAdapter());
        }
      } catch (_) {}
      final box = await Hive.openBox<VisitaMonitoreo>('visitas_monitoreo');
      await box.add(nuevaVisita);

      // 3. Si estamos online, intentar sincronizar inmediatamente
      if (_isOnline) {
        await SyncService.syncAllPendingData();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Visita registrada. Se sincronizará pronto.')),
        );
        Navigator.pop(
          context,
          true,
        ); // Devuelve true para refrescar la pantalla anterior
      }
    } catch (e) {
      debugPrint('Error en _guardarVisita: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar la visita: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (_isOnline && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
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
                      HistorialVisitasParcela(parcelaUuid: widget.parcelaUuid),
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
                                    DataColumn(label: Text('Planta 1')),
                                    DataColumn(label: Text('Planta 2')),
                                    DataColumn(label: Text('Planta 3')),
                                    DataColumn(label: Text('Planta 4')),
                                    DataColumn(label: Text('Planta 5')),
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
