import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:cardegua/sync_service.dart';
import 'package:cardegua/visita_parcela.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- NUEVO: Estado para la carga del municipio ---
enum MunicipioStatus { loading, loaded, offline, error }
// --- FIN NUEVO ---

class HistorialVisitasParcela extends StatefulWidget {
  final String parcelaUuid;
  const HistorialVisitasParcela({super.key, required this.parcelaUuid});
  @override
  State<HistorialVisitasParcela> createState() =>
      _HistorialVisitasParcelaState();
}

class _HistorialVisitasParcelaState extends State<HistorialVisitasParcela> {
  List<VisitaMonitoreo> _visitas = [];
  bool _isLoading = true;
  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // --- MODIFICADO: Variables de estado para el municipio ---
  String? _municipioNombre;
  int? _municipioId;
  double? _municipioHistorico; // <-- NUEVO: Para guardar el valor numérico
  MunicipioStatus _municipioStatus = MunicipioStatus.loading;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController
  _nombreController; // <-- Renombrado (antes _municipioController)
  late TextEditingController _historicoController; // <-- NUEVO
  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _historicoController = TextEditingController();
    _initAndLoadData();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _nombreController.dispose();
    _historicoController.dispose();
    super.dispose();
  }

  Future<void> _initAndLoadData() async {
    final conn = Connectivity();
    final initialResult = await conn.checkConnectivity();
    if (mounted) {
      setState(
        () => _isOnline =
            initialResult.contains(ConnectivityResult.mobile) ||
            initialResult.contains(ConnectivityResult.wifi),
      );
    }

    _connectivitySub = conn.onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(
          () => _isOnline =
              result.contains(ConnectivityResult.mobile) ||
              result.contains(ConnectivityResult.wifi),
        );
      }
    });

    // Cargar datos del municipio
    await _loadMunicipioData();

    if (_isOnline) {
      await _manualRefreshVisitas();
    } else {
      await _loadLocalVisitas();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- MODIFICADO: Función para cargar los datos del municipio ---
  // --- MODIFICADO: Función para cargar los datos del municipio ---
  Future<void> _loadMunicipioData() async {
    if (mounted) setState(() => _municipioStatus = MunicipioStatus.loading);

    if (!_isOnline) {
      debugPrint(
        '[Historial] Sin conexión, no se pueden cargar datos del municipio.',
      );
      if (mounted) setState(() => _municipioStatus = MunicipioStatus.offline);
      return;
    }

    try {
      final parcelaResponse = await Supabase.instance.client
          .from('parcelas')
          .select('id_municipio')
          .eq('uuid', widget.parcelaUuid)
          .single();

      final municipioId = parcelaResponse['id_municipio'] as int?;

      if (municipioId == null) {
        throw Exception('La parcela no tiene un municipio asignado.');
      }

      final municipioResponse = await Supabase.instance.client
          .from('municipios')
          .select('id_municipio, nombre, historico')
          .eq('id_municipio', municipioId)
          .single();

      if (mounted) {
        setState(() {
          _municipioNombre = municipioResponse['nombre'] as String?;

          // --- ¡ESTA ES LA CORRECCIÓN! ---
          // Manejar explícitamente el valor nulo de la base de datos
          final historicoValue = municipioResponse['historico'];
          if (historicoValue == null) {
            _municipioHistorico = null; // Guardar como nulo
          } else {
            // Si no es nulo, es un 'num' (int o double), convertir a double
            _municipioHistorico = (historicoValue as num).toDouble();
          }
          // --- FIN DE LA CORRECCIÓN ---

          _municipioId = municipioResponse['id_municipio'] as int?;
          _municipioStatus = MunicipioStatus.loaded;
        });
      }
    } catch (e) {
      debugPrint('Error en _loadMunicipioData: $e');
      if (mounted) {
        setState(() => _municipioStatus = MunicipioStatus.error);
      }
    }
  }
  // --- FIN MODIFICADO ---

  Future<void> _fetchRemoteVisitas() async {
    if (!_isOnline) return;
    debugPrint('[Historial] Descargando visitas remotas...');
    try {
      final box = await Hive.openBox<VisitaMonitoreo>('visitas_monitoreo');

      final response = await Supabase.instance.client
          .from('visitas_monitoreo')
          .select()
          .eq('uuid_parcelas', widget.parcelaUuid);

      final remoteVisitas = List<Map<String, dynamic>>.from(response);
      debugPrint(
        '[Historial] Se encontraron ${remoteVisitas.length} visitas en el servidor.',
      );

      for (final remoteData in remoteVisitas) {
        final visita = VisitaMonitoreo.fromJson(remoteData);

        VisitaMonitoreo? localVisita;
        try {
          localVisita = box.values.firstWhere((v) => v.uuid == visita.uuid);
        } catch (_) {
          localVisita = null;
        }

        if (localVisita != null) {
          if (localVisita.status != 'pending') {
            await box.put(localVisita.key, visita);
          }
        } else {
          await box.add(visita);
        }
      }
    } catch (e) {
      debugPrint('Error en _fetchRemoteVisitas: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar historial: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _loadLocalVisitas() async {
    try {
      if (!Hive.isAdapterRegistered(VisitaMonitoreoAdapter().typeId)) {
        Hive.registerAdapter(VisitaMonitoreoAdapter());
      }
    } catch (_) {}
    final box = await Hive.openBox<VisitaMonitoreo>('visitas_monitoreo');
    final allVisitas = box.values
        .where(
          (visita) =>
              visita.parcelaUuid == widget.parcelaUuid &&
              visita.operation != 'delete',
        )
        .toList();

    allVisitas.sort((a, b) {
      final dateA = DateTime.tryParse(a.fechaVisita);
      final dateB = DateTime.tryParse(b.fechaVisita);
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    if (mounted) setState(() => _visitas = allVisitas);
  }

  Future<void> _manualRefreshVisitas() async {
    if (_isOnline) {
      await _fetchRemoteVisitas();
      await SyncService.syncAllPendingData();
    }
    await _loadLocalVisitas();
  }

  Future<void> _fullManualRefresh() async {
    setState(() => _isLoading = true);

    // Recargar ambos
    await _loadMunicipioData();
    await _manualRefreshVisitas();

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOnline ? 'Historial actualizado.' : 'Mostrando datos locales.',
          ),
        ),
      );
    }
  }

  // --- MODIFICADO: Widget para mostrar y editar el municipio ---
  Widget _buildMunicipioInfo() {
    final natureGreen = const Color(0xFF6DB571);

    String displayText;
    Color textColor;
    IconData icon;
    Color iconColor;
    String tooltip;
    VoidCallback? onPressed;

    switch (_municipioStatus) {
      // Estado de carga
      case MunicipioStatus.loading:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Center(
            child: Text(
              'Cargando municipio...',
              style: GoogleFonts.montserrat(color: Colors.grey.shade600),
            ),
          ),
        );

      // Cargado correctamente
      case MunicipioStatus.loaded:
        displayText = 'Municipio: $_municipioNombre';
        textColor = Colors.black87;
        icon = Icons.edit;
        // Revisar si hay conexión para habilitar la edición
        iconColor = _isOnline ? natureGreen : Colors.grey;
        tooltip = _isOnline ? 'Editar Municipio' : 'Se requiere conexión';
        onPressed = _isOnline ? _showEditMunicipioDialog : null;
        break;

      // Sin conexión
      case MunicipioStatus.offline:
        displayText = 'Municipio: (Sin conexión)';
        textColor = Colors.grey.shade600;
        icon = Icons.edit_off; // Icono de editar deshabilitado
        iconColor = Colors.grey;
        tooltip = 'Se requiere conexión para editar';
        onPressed = null;
        break;

      // Error al cargar
      case MunicipioStatus.error:
        displayText = 'Municipio: (Error al cargar)';
        textColor = Colors.red.shade700;
        icon = Icons.error_outline; // Icono de error
        iconColor = Colors.grey;
        tooltip = 'No se pudo cargar el municipio';
        onPressed = null;
        break;
    }

    // Widget final
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              displayText, // Usar variable
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor, // Usar variable
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(icon, color: iconColor), // Usar variables
            tooltip: tooltip, // Usar variable
            onPressed: onPressed, // Usar variable
          ),
        ],
      ),
    );
  }

  // --- FIN MODIFICADO ---
  // --- MODIFICADO: Diálogo para editar el municipio ---
  Future<void> _showEditMunicipioDialog() async {
    // Cargar los datos actuales en los campos de texto
    _nombreController.text = _municipioNombre ?? '';
    _historicoController.text = _municipioHistorico?.toString() ?? '0.0';

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final natureGreen = const Color(0xFF6DB571);
        return AlertDialog(
          title: Text(
            'Editar Municipio',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    // --- CORRECCIÓN 1: Usar el controller de 'nombre' ---
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del Municipio',
                      border: OutlineInputBorder(),
                      enabled: false, // <-- Hacer el campo no editable
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El nombre no puede estar vacío';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16), // <-- NUEVO espacio
                  // --- NUEVO: Campo para 'historico' ---
                  TextFormField(
                    controller: _historicoController,
                    decoration: const InputDecoration(
                      labelText: 'Valor Histórico',
                      border: OutlineInputBorder(),
                    ),
                    // Asegurarse de que solo se ingresen números
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El valor no puede estar vacío';
                      }
                      // --- CORRECCIÓN 3: Validar que sea un double ---
                      if (double.tryParse(value) == null) {
                        return 'Debe ser un número válido (ej. 12.5)';
                      }
                      return null;
                    },
                  ),
                  // --- FIN NUEVO ---
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancelar', style: GoogleFonts.montserrat()),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: natureGreen),
              child: Text(
                'Guardar',
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _updateMunicipio(dialogContext);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // --- MODIFICADO: Lógica para guardar el municipio ---
  // --- MODIFICADO: Lógica para guardar el municipio ---
  Future<void> _updateMunicipio(BuildContext dialogContext) async {
    // --- CORRECCIÓN 1: Leer ambos controllers ---
    final nuevoNombre = _nombreController.text.trim();
    // Convertir el texto 'historico' de nuevo a un número (double)
    final nuevoHistorico = double.tryParse(_historicoController.text.trim());
    if (_municipioId == null || nuevoHistorico == null) {
      // Si el número es inválido (no debería pasar por el validador, pero es un chequeo)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valor histórico inválido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client
          .from('municipios')
          // --- CORRECCIÓN 2: Actualizar ambos campos ---
          .update({
            'nombre': nuevoNombre,
            'historico': nuevoHistorico, // <-- NUEVO
          })
          .eq('id_municipio', _municipioId!);

      if (mounted) {
        setState(() {
          // --- CORRECCIÓN 3: Actualizar ambas variables locales ---
          _municipioNombre = nuevoNombre;
          _municipioHistorico = nuevoHistorico; // <-- NUEVO
          _municipioStatus = MunicipioStatus.loaded;
        });
      }
      Navigator.of(dialogContext).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Municipio actualizado correctamente.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error en _updateMunicipio: $e');
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildConteoGeneral(VisitaMonitoreo visita) {
    // ... (Tu código existente, sin cambios)
    final conteos = {
      'EP': visita.ep,
      'AP': visita.ap,
      'MP': visita.mp,
      'BP': visita.bp,
      'CP': visita.cp,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conteo General:',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: conteos.entries.map((entry) {
              return Chip(
                label: Text(
                  '${entry.key}: ${entry.value ?? 0}',
                  style: GoogleFonts.montserrat(fontSize: 12),
                ),
                backgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoreoPlantas(VisitaMonitoreo visita) {
    // ... (Tu código existente, sin cambios)
    try {
      final List<dynamic> monitoreoData = jsonDecode(
        visita.monitoreoPlantasJson,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monitoreo de Plantas:',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 40,
                dataRowMinHeight: 35,
                dataRowMaxHeight: 40,
                columns: const [
                  DataColumn(label: Text('Situación')),
                  DataColumn(label: Text('EP')),
                  DataColumn(label: Text('AP')),
                  DataColumn(label: Text('MP')),
                  DataColumn(label: Text('BP')),
                  DataColumn(label: Text('CP')),
                ],
                rows: [
                  _buildDataRow('Tallos', 'tallos_florales', monitoreoData),
                  _buildDataRow('Ejes', 'eje_floral', monitoreoData),
                  _buildDataRow('Flores', 'flores', monitoreoData),
                  _buildDataRow(
                    'Frutos s/Daño',
                    'frutos_sin_dano',
                    monitoreoData,
                  ),
                  _buildDataRow('c/Picudo', 'frutos_con_picudo', monitoreoData),
                  _buildDataRow('c/Trips', 'frutos_con_trips', monitoreoData),
                  _buildDataRow(
                    's/Cosechar',
                    'frutos_sin_cosechar',
                    monitoreoData,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return Text('Error al mostrar datos de monitoreo: $e');
    }
  }

  DataRow _buildDataRow(String label, String key, List<dynamic> data) {
    // ... (Tu código existente, sin cambios)
    return DataRow(
      cells: [
        DataCell(Text(label, style: GoogleFonts.montserrat(fontSize: 12))),
        for (int i = 0; i < 5; i++)
          DataCell(
            Center(
              child: Text((data.length > i ? data[i][key] ?? 0 : 0).toString()),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final natureGreen = const Color(0xFF6DB571);
    final backgroundNature = const Color(0xFFEAFBE7);

    return Scaffold(
      backgroundColor: backgroundNature,
      appBar: AppBar(
        backgroundColor: natureGreen,
        title: Text(
          'Historial de Visitas',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      // --- MODIFICADO: Envuelto en un Column (sin cambios) ---
      body: Column(
        children: [
          // --- NUEVO: Widget del municipio (ahora siempre visible) ---
          _buildMunicipioInfo(),
          // --- NUEVO: Expanded para la lista (sin cambios) ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fullManualRefresh,
                    child: _visitas.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history_toggle_off,
                                    size: 80,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No hay visitas registradas para esta parcela.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: _visitas.length,
                            itemBuilder: (context, index) {
                              final visita = _visitas[index];
                              final fecha = DateTime.tryParse(
                                visita.fechaVisita,
                              );
                              final formattedDate = fecha != null
                                  ? DateFormat('dd/MM/yyyy').format(fecha)
                                  : 'Fecha inválida';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ExpansionTile(
                                  backgroundColor: Colors.white,
                                  collapsedBackgroundColor: Colors.white,
                                  leading: CircleAvatar(
                                    backgroundColor: natureGreen.withOpacity(
                                      0.1,
                                    ),
                                    child: Icon(
                                      Icons.calendar_today,
                                      color: natureGreen,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    'Visita del $formattedDate',
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.bold,
                                      color: natureGreen,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: visita.status == 'pending'
                                      ? Row(
                                          children: [
                                            const Icon(
                                              Icons.sync_problem,
                                              color: Colors.orange,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pendiente de sincronizar',
                                              style: GoogleFonts.montserrat(
                                                color: Colors.orange,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ).copyWith(bottom: 16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Divider(height: 1),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Observaciones:',
                                            style: GoogleFonts.montserrat(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            visita.observaciones ??
                                                'Sin observaciones.',
                                            style: GoogleFonts.montserrat(
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Recomendaciones:',
                                            style: GoogleFonts.montserrat(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            visita.recomendaciones ??
                                                'Sin recomendaciones.',
                                            style: GoogleFonts.montserrat(
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          _buildConteoGeneral(visita),
                                          _buildMonitoreoPlantas(visita),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
