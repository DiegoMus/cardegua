import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class HistorialVisitasParcela extends StatefulWidget {
  final String parcelaId;

  const HistorialVisitasParcela({super.key, required this.parcelaId});

  @override
  State<HistorialVisitasParcela> createState() =>
      _HistorialVisitasParcelaState();
}

class _HistorialVisitasParcelaState extends State<HistorialVisitasParcela> {
  List<dynamic> visitas = [];
  bool loading = false;

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _fetchVisitas();
  }

  Future<void> _fetchVisitas() async {
    setState(() => loading = true);
    final supabase = Supabase.instance.client;

    try {
      // Intenta convertir parcelaId a int si corresponde
      dynamic parcelaIdToQuery = widget.parcelaId;
      final parsed = int.tryParse(widget.parcelaId);
      if (parsed != null) parcelaIdToQuery = parsed;

      // Consulta las visitas de la parcela ordenadas por fecha de visita (desc)
      final res = await supabase
          .from('visitas_monitoreo')
          .select()
          .eq('id_parcela', parcelaIdToQuery);

      // Cuando la API devuelve PostgREST, viene como List<dynamic>
      setState(() {
        visitas = res as List<dynamic>? ?? [];
      });
    } catch (e) {
      // Si hay error, mostrar snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar historial: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // Extrae un posible id primario del registro de la visita.
  // Busca claves que empiecen por "id" y que no sean "id_parcela".
  String? _findPrimaryKeyName(Map<String, dynamic> visit) {
    for (final k in visit.keys) {
      final lower = k.toLowerCase();
      if (lower == 'id_parcela') continue;
      // heurística: preferir keys que comiencen con "id"
      if (lower.startsWith('id')) return k;
    }
    // fallback: keys que contienen 'id' en cualquier parte (pero no id_parcela)
    for (final k in visit.keys) {
      final lower = k.toLowerCase();
      if (lower.contains('id') && lower != 'id_parcela') return k;
    }
    return null;
  }

  Future<void> _deleteVisita(Map<String, dynamic> visit) async {
    final supabase = Supabase.instance.client;

    final pkName = _findPrimaryKeyName(visit);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: const Text('¿Deseas eliminar esta visita?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Intenta borrar por la pk encontrada, si no existe usa match por id_parcela + fecha_visita
      if (pkName != null && visit[pkName] != null) {
        await supabase
            .from('visita_parcela')
            .delete()
            .eq(pkName, visit[pkName]);
      } else {
        // fallback — intentar eliminar por id_parcela y fecha_registro_sistema o fecha_visita
        dynamic parcelaIdToQuery = widget.parcelaId;
        final parsed = int.tryParse(widget.parcelaId);
        if (parsed != null) parcelaIdToQuery = parsed;

        if (visit['fecha_registro_sistema'] != null) {
          await supabase.from('visita_parcela').delete().match({
            'id_parcela': parcelaIdToQuery,
            'fecha_registro_sistema': visit['fecha_registro_sistema'],
          });
        } else if (visit['fecha_visita'] != null) {
          await supabase.from('visita_parcela').delete().match({
            'id_parcela': parcelaIdToQuery,
            'fecha_visita': visit['fecha_visita'],
          });
        } else {
          throw Exception(
            'No se pudo determinar cómo eliminar el registro (falta clave primaria/fechas).',
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Visita eliminada')));
        await _fetchVisitas();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar la visita: $e')),
        );
      }
    }
  }

  Widget _buildMonitoreoTable(List<dynamic>? listaMonitoreo) {
    if (listaMonitoreo == null || listaMonitoreo.isEmpty) {
      return const Text('Sin datos de monitoreo.');
    }

    // Construir una tabla simple mostrando planta y sus conteos
    return Column(
      children: [
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(
                label: Text(
                  'Planta',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Tallos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Eje',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Flores',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Sin daño',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Picudo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Trips',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Mosca',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Sin cosechar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows: listaMonitoreo.map((m) {
              final planta = (m['planta'] ?? '').toString();
              final tallos = (m['tallos_florales'] ?? '').toString();
              final eje = (m['eje_floral'] ?? '').toString();
              final flores = (m['flores'] ?? '').toString();
              final sinDano = (m['frutos_sin_dano'] ?? '').toString();
              final picudo = (m['frutos_con_picudo'] ?? '').toString();
              final trips = (m['frutos_con_trips'] ?? '').toString();
              final mosca = (m['frutos_con_mosca'] ?? '').toString();
              final sinCosechar = (m['frutos_sin_cosechar'] ?? '').toString();

              return DataRow(
                cells: [
                  DataCell(Text(planta)),
                  DataCell(Text(tallos)),
                  DataCell(Text(eje)),
                  DataCell(Text(flores)),
                  DataCell(Text(sinDano)),
                  DataCell(Text(picudo)),
                  DataCell(Text(trips)),
                  DataCell(Text(mosca)),
                  DataCell(Text(sinCosechar)),
                ],
              );
            }).toList(),
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
          style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              key: _refreshKey,
              onRefresh: _fetchVisitas,
              child: visitas.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No hay visitas registradas para esta parcela.',
                            style: GoogleFonts.montserrat(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: visitas.length,
                      itemBuilder: (context, index) {
                        final visit = visitas[index] as Map<String, dynamic>;
                        // Fecha: puede venir en iso string o como timestamptz
                        String fechaTexto = '';
                        if (visit['fecha_visita'] != null) {
                          try {
                            final raw = visit['fecha_visita'];
                            DateTime dt;
                            if (raw is String) {
                              dt = DateTime.parse(raw).toLocal();
                            } else if (raw is DateTime) {
                              dt = raw.toLocal();
                            } else {
                              // a veces viene como Map {'_seconds':...} en otros clientes; intentar parse
                              dt =
                                  DateTime.tryParse(raw.toString()) ??
                                  DateTime.now();
                            }
                            fechaTexto = _dateFormat.format(dt);
                          } catch (_) {
                            fechaTexto = visit['fecha_visita'].toString();
                          }
                        }

                        final usuario =
                            (visit['usuario_registro_email'] ??
                                    visit['usuario_registro_id'] ??
                                    'Desconocido')
                                .toString();

                        final ep = visit['ep']?.toString() ?? '0';
                        final ap = visit['ap']?.toString() ?? '0';
                        final mp = visit['mp']?.toString() ?? '0';
                        final bp = visit['bp']?.toString() ?? '0';
                        final cp = visit['cp']?.toString() ?? '0';

                        final monitoreo =
                            visit['monitoreo_plantas'] as List<dynamic>?;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: natureGreen.withOpacity(0.15),
                              child: Icon(
                                Icons.calendar_today,
                                color: natureGreen,
                              ),
                            ),
                            title: Text(
                              fechaTexto.isEmpty
                                  ? 'Fecha desconocida'
                                  : fechaTexto,
                              style: GoogleFonts.montserrat(
                                color: natureGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              usuario,
                              style: GoogleFonts.montserrat(fontSize: 12),
                            ),
                            childrenPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: natureGreen),
                              onSelected: (value) {
                                if (value == 'delete') {
                                  _deleteVisita(visit);
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text(
                                        'Eliminar',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              // Conteo general (EP/AP/...)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _smallStat('EP', ep),
                                  _smallStat('AP', ap),
                                  _smallStat('MP', mp),
                                  _smallStat('BP', bp),
                                  _smallStat('CP', cp),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Observaciones / Recomendaciones
                              if ((visit['observaciones'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Observaciones',
                                      style: GoogleFonts.montserrat(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      visit['observaciones'].toString(),
                                      style: GoogleFonts.montserrat(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              if ((visit['recomendaciones'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Recomendaciones',
                                      style: GoogleFonts.montserrat(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      visit['recomendaciones'].toString(),
                                      style: GoogleFonts.montserrat(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              // Tabla de monitoreo (si existe)
                              _buildMonitoreoTable(monitoreo),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _smallStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            value,
            style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
