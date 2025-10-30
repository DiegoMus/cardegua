import 'dart:async';
import 'dart:convert';
import 'package:cardegua/sync_service.dart';
import 'package:cardegua/visita_parcela.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _initAndLoadData();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoadData() async {
    final conn = Connectivity();
    final initialResult = await conn.checkConnectivity();
    if (mounted)
      setState(
        () => _isOnline =
            initialResult.contains(ConnectivityResult.mobile) ||
            initialResult.contains(ConnectivityResult.wifi),
      );

    _connectivitySub = conn.onConnectivityChanged.listen((result) {
      if (mounted)
        setState(
          () => _isOnline =
              result.contains(ConnectivityResult.mobile) ||
              result.contains(ConnectivityResult.wifi),
        );
    });

    // LÓGICA DE INICIO MEJORADA
    if (_isOnline) {
      await _manualRefresh(); // Si hay internet, refresca al entrar
    } else {
      await _loadLocalVisitas(); // Si no, solo carga lo local
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- NUEVA FUNCIÓN PARA DESCARGAR VISITAS DEL SERVIDOR ---
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
        final uuid = remoteData['uuid'] as String?;
        if (uuid == null) continue;

        VisitaMonitoreo? localVisita;
        try {
          localVisita = box.values.firstWhere((v) => v.uuid == uuid);
        } catch (_) {
          localVisita = null;
        }

        final visita = VisitaMonitoreo(
          serverId: remoteData['id_visita'],
          uuid: uuid,
          parcelaUuid: remoteData['uuid_parcelas'] ?? widget.parcelaUuid,
          parcelaId: remoteData['id_parcela'],
          fechaVisita: remoteData['fecha_visita'],
          observaciones: remoteData['observaciones'],
          recomendaciones: remoteData['recomendaciones'],
          ep: remoteData['ep'],
          ap: remoteData['ap'],
          mp: remoteData['mp'],
          bp: remoteData['bp'],
          cp: remoteData['cp'],
          monitoreoPlantasJson: jsonEncode(
            remoteData['monitoreo_plantas'] ?? [],
          ),
          usuarioRegistroId: remoteData['usuario_registro_id'],
          usuarioRegistroEmail: remoteData['usuario_registro_email'],
          status: 'synced',
          operation: null,
        );

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
    allVisitas.sort(
      (a, b) => DateTime.parse(
        b.fechaVisita,
      ).compareTo(DateTime.parse(a.fechaVisita)),
    );
    if (mounted) setState(() => _visitas = allVisitas);
  }

  // --- FUNCIÓN DE REFRESCO MEJORADA ---
  Future<void> _manualRefresh() async {
    setState(() => _isLoading = true);
    if (_isOnline) {
      await _fetchRemoteVisitas(); // 1. DESCARGA
      await SyncService.syncAllPendingData(); // 2. ENVÍA
    }
    await _loadLocalVisitas(); // 3. MUESTRA DESDE LOCAL
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

  Widget _buildConteoGeneral(VisitaMonitoreo visita) {
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
                  _buildDataRow('c/Mosca', 'frutos_con_mosca', monitoreoData),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _manualRefresh,
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
                      padding: const EdgeInsets.all(12),
                      itemCount: _visitas.length,
                      itemBuilder: (context, index) {
                        final visita = _visitas[index];
                        final fecha = DateTime.tryParse(visita.fechaVisita);
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
                              backgroundColor: natureGreen.withOpacity(0.1),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}
