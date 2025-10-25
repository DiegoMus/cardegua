import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'visita_parcela.dart';

// --- Funciones de ayuda ---
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
  if (v is num) return v.toDouble();
  final s = v.toString().replaceAll(',', '.');
  return double.tryParse(s);
}

// --- Modelo Hive: Parcela ---
@HiveType(typeId: 10)
class Parcela extends HiveObject {
  @HiveField(0)
  int? serverId;
  @HiveField(1)
  String nombre;
  @HiveField(2)
  double? area;
  @HiveField(3)
  String? tipoCultivoNombre;
  @HiveField(4)
  int? idTipoCultivo;
  @HiveField(5)
  double? latitud;
  @HiveField(6)
  double? longitud;
  @HiveField(7)
  double? altitud;
  @HiveField(8)
  int? idMunicipio;
  @HiveField(9)
  bool vigente;
  @HiveField(10)
  String? fechaRegistroIso;
  @HiveField(11)
  String? operation;
  @HiveField(12)
  String status;
  @HiveField(13)
  String updatedAt;
  @HiveField(14)
  int? productorId;

  Parcela({
    this.serverId,
    required this.nombre,
    this.area,
    this.tipoCultivoNombre,
    this.idTipoCultivo,
    this.latitud,
    this.longitud,
    this.altitud,
    this.idMunicipio,
    this.vigente = true,
    this.fechaRegistroIso,
    this.operation,
    this.status = 'pending',
    String? updatedAt,
    this.productorId,
  }) : updatedAt = updatedAt ?? DateTime.now().toIso8601String();
}

// --- Adapter de Hive para Parcela ---
class ParcelaAdapter extends TypeAdapter<Parcela> {
  @override
  final int typeId = 10;

  @override
  Parcela read(BinaryReader reader) {
    final n = reader.readByte();
    final m = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return Parcela(
      serverId: _toNullableInt(m[0]),
      nombre: (m[1] ?? '').toString(),
      area: _toNullableDouble(m[2]),
      tipoCultivoNombre: m[3] as String?,
      idTipoCultivo: _toNullableInt(m[4]),
      latitud: _toNullableDouble(m[5]),
      longitud: _toNullableDouble(m[6]),
      altitud: _toNullableDouble(m[7]),
      idMunicipio: _toNullableInt(m[8]),
      vigente: m[9] as bool? ?? true,
      fechaRegistroIso: m[10] as String?,
      operation: m[11] as String?,
      status: (m[12] as String?) ?? 'pending',
      updatedAt: m[13] as String?,
      productorId: _toNullableInt(m[14]),
    );
  }

  @override
  void write(BinaryWriter writer, Parcela obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.serverId)
      ..writeByte(1)
      ..write(obj.nombre)
      ..writeByte(2)
      ..write(obj.area)
      ..writeByte(3)
      ..write(obj.tipoCultivoNombre)
      ..writeByte(4)
      ..write(obj.idTipoCultivo)
      ..writeByte(5)
      ..write(obj.latitud)
      ..writeByte(6)
      ..write(obj.longitud)
      ..writeByte(7)
      ..write(obj.altitud)
      ..writeByte(8)
      ..write(obj.idMunicipio)
      ..writeByte(9)
      ..write(obj.vigente)
      ..writeByte(10)
      ..write(obj.fechaRegistroIso)
      ..writeByte(11)
      ..write(obj.operation)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.updatedAt)
      ..writeByte(14)
      ..write(obj.productorId);
  }
}

// --- Página de Parcelas ---
class ParcelasPage extends StatefulWidget {
  final int productorId;
  final String nombreProductor;

  const ParcelasPage({
    super.key,
    required this.productorId,
    required this.nombreProductor,
  });

  @override
  State<ParcelasPage> createState() => _ParcelasPageState();
}

class _ParcelasPageState extends State<ParcelasPage>
    with SingleTickerProviderStateMixin {
  List<Parcela> parcelas = [];
  List<Parcela> filteredParcelas = [];
  bool loading = false;

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _areaController = TextEditingController();
  final _tipoCultivoController = TextEditingController();
  final _municipioController = TextEditingController();
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  final _altitudController = TextEditingController();
  final _searchController = TextEditingController();
  bool _vigente = true;
  DateTime? _fechaRegistro;

  int? _selectedTipoCultivoId;
  int? _selectedMunicipioId;

  late AnimationController _animationController;
  bool isEditing = false;
  Parcela? editingParcela;
  bool showForm = false;

  final Set<int> _recentlyVisitedIds = {};
  final Duration _highlightDuration = const Duration(seconds: 4);

  late Box<Parcela> _parcelaBox;
  late Box _tipoCultivoBox;
  late Box _municipiosBox;

  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _searchController.addListener(() {
      loadLocalParcelas();
    });

    if (widget.productorId == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este productor no está sincronizado. No se pueden añadir parcelas.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    }

    _openBoxesAndInit();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nombreController.dispose();
    _areaController.dispose();
    _tipoCultivoController.dispose();
    _municipioController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    _altitudController.dispose();
    _searchController.dispose();
    _connectivitySub.cancel();
    super.dispose();
  }

  Future<void> _openBoxesAndInit() async {
    try {
      if (!Hive.isAdapterRegistered(ParcelaAdapter().typeId)) {
        Hive.registerAdapter(ParcelaAdapter());
      }
    } catch (_) {}

    if (!Hive.isBoxOpen('parcelas')) await Hive.openBox<Parcela>('parcelas');
    if (!Hive.isBoxOpen('catalog_tipo_cultivo'))
      await Hive.openBox('catalog_tipo_cultivo');
    if (!Hive.isBoxOpen('catalog_municipios'))
      await Hive.openBox('catalog_municipios');

    _parcelaBox = Hive.box<Parcela>('parcelas');
    _tipoCultivoBox = Hive.box('catalog_tipo_cultivo');
    _municipiosBox = Hive.box('catalog_municipios');

    await loadLocalParcelas();

    final connectivity = Connectivity();
    final initialStatus = await connectivity.checkConnectivity();
    _isOnline = _normalizeConnectivity(initialStatus);
    if (mounted) setState(() {});

    _connectivitySub = connectivity.onConnectivityChanged.listen((result) {
      final newStatus = _normalizeConnectivity(result);
      if (_isOnline != newStatus) {
        if (mounted)
          setState(() {
            _isOnline = newStatus;
          });
        if (newStatus) {
          manualRefresh();
        }
      }
    });

    if (_isOnline) {
      await manualRefresh();
    }
  }

  bool _normalizeConnectivity(List<ConnectivityResult> result) {
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi);
  }

  Future<void> loadLocalParcelas() async {
    parcelas = _parcelaBox.values
        .where(
          (p) => p.operation != 'delete' && p.productorId == widget.productorId,
        )
        .toList();

    final search = _searchController.text.toLowerCase();
    if (search.isNotEmpty) {
      filteredParcelas = parcelas.where((p) {
        return p.nombre.toLowerCase().contains(search) ||
            (p.tipoCultivoNombre ?? '').toLowerCase().contains(search);
      }).toList();
    } else {
      filteredParcelas = List.from(parcelas);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> manualRefresh() async {
    if (!mounted) return;
    setState(() => loading = true);

    if (_isOnline) {
      await syncPending();
      await _syncCatalogsFromServer();
      await fetchParcelas();
    } else {
      await loadLocalParcelas();
    }

    if (mounted) {
      setState(() => loading = false);
      _animationController.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOnline
                ? 'Actualización completada.'
                : 'Mostrando datos locales.',
          ),
          backgroundColor: _isOnline ? Colors.green : Colors.blueGrey,
        ),
      );
    }
  }

  Future<void> _syncCatalogsFromServer() async {
    if (!_isOnline) return;
    try {
      final supabase = Supabase.instance.client;
      final resTipo = await supabase.from('tipo_cultivo').select('id, cultivo');
      await _tipoCultivoBox.clear();
      for (final e in resTipo) {
        _tipoCultivoBox.put(e['id'].toString(), e);
      }

      final resMun = await supabase
          .from('municipios')
          .select('id_municipio, nombre');
      await _municipiosBox.clear();
      for (final e in resMun) {
        _municipiosBox.put(e['id_municipio'].toString(), e);
      }
    } catch (e) {
      debugPrint('Error sincronizando catálogos: $e');
    }
  }

  Future<void> syncPending() async {
    if (!_isOnline) return;
    final supabase = Supabase.instance.client;
    final pending = _parcelaBox.values
        .where((p) => p.status == 'pending')
        .toList();

    for (final p in pending) {
      try {
        if (p.operation == 'create') {
          final res = await supabase
              .from('parcelas')
              .insert({
                'nombre': p.nombre,
                'area': p.area,
                'id_tipo_cultivo': p.idTipoCultivo,
                'latitud': p.latitud,
                'longitud': p.longitud,
                'altitud': p.altitud,
                'id_municipio': p.idMunicipio,
                'id_productor': p.productorId,
                'fecha_registro': p.fechaRegistroIso,
                'vigente': p.vigente,
              })
              .select()
              .single();
          p.serverId = res['id_parcela'];
          p.operation = null;
          p.status = 'synced';
          await p.save();
        } else if (p.operation == 'update' && p.serverId != null) {
          await supabase
              .from('parcelas')
              .update({
                'nombre': p.nombre,
                'area': p.area,
                'id_tipo_cultivo': p.idTipoCultivo,
                'latitud': p.latitud,
                'longitud': p.longitud,
                'altitud': p.altitud,
                'id_municipio': p.idMunicipio,
                'vigente': p.vigente,
              })
              .eq('id_parcela', p.serverId!);
          p.operation = null;
          p.status = 'synced';
          await p.save();
        } else if (p.operation == 'delete') {
          if (p.serverId != null) {
            await supabase
                .from('parcelas')
                .delete()
                .eq('id_parcela', p.serverId!);
          }
          await p.delete();
        }
      } catch (e) {
        debugPrint('Error sincronizando parcela ${p.key}: $e');
      }
    }
    await loadLocalParcelas();
  }

  Future<void> fetchParcelas() async {
    if (!_isOnline) {
      await loadLocalParcelas();
      return;
    }
    try {
      final result = await Supabase.instance.client
          .from('parcelas')
          .select('*, tipo_cultivo(cultivo)')
          .eq('id_productor', widget.productorId);

      for (final r in result) {
        final serverId = _toNullableInt(r['id_parcela']);
        if (serverId == null) continue;

        final local = _parcelaBox.values.firstWhere(
          (p) => p.serverId == serverId,
          orElse: () => Parcela(nombre: '', productorId: widget.productorId),
        );

        if (local.key == null || local.operation == null) {
          final newP = Parcela(
            serverId: serverId,
            nombre: r['nombre'] ?? '',
            area: _toNullableDouble(r['area']),
            tipoCultivoNombre: r['tipo_cultivo'] != null
                ? r['tipo_cultivo']['cultivo']
                : null,
            idTipoCultivo: _toNullableInt(r['id_tipo_cultivo']),
            latitud: _toNullableDouble(r['latitud']),
            longitud: _toNullableDouble(r['longitud']),
            altitud: _toNullableDouble(r['altitud']),
            idMunicipio: _toNullableInt(r['id_municipio']),
            vigente: r['vigente'] ?? true,
            fechaRegistroIso: r['fecha_registro'],
            productorId: _toNullableInt(r['id_productor']),
            status: 'synced',
          );
          if (local.key != null) {
            await _parcelaBox.put(local.key, newP);
          } else {
            await _parcelaBox.add(newP);
          }
        }
      }
    } catch (e) {
      debugPrint('Error en fetchParcelas: $e');
    } finally {
      await loadLocalParcelas();
    }
  }

  void clearFormFields() {
    _nombreController.clear();
    _areaController.clear();
    _tipoCultivoController.clear();
    _municipioController.clear();
    _latitudController.clear();
    _longitudController.clear();
    _altitudController.clear();
    setState(() {
      _vigente = true;
      _fechaRegistro = null;
      isEditing = false;
      editingParcela = null;
      _selectedTipoCultivoId = null;
      _selectedMunicipioId = null;
      showForm = false;
    });
  }

  Future<void> addOrUpdateParcela() async {
    if (!_formKey.currentState!.validate()) return;

    final p = isEditing
        ? editingParcela!
        : Parcela(productorId: widget.productorId, nombre: '');

    p.nombre = _nombreController.text;
    p.area = _toNullableDouble(_areaController.text);
    p.tipoCultivoNombre = _tipoCultivoController.text;
    p.idTipoCultivo = _selectedTipoCultivoId;
    p.latitud = _toNullableDouble(_latitudController.text);
    p.longitud = _toNullableDouble(_longitudController.text);
    p.altitud = _toNullableDouble(_altitudController.text);
    p.idMunicipio = _selectedMunicipioId;
    p.vigente = _vigente;
    p.fechaRegistroIso = (_fechaRegistro ?? DateTime.now()).toIso8601String();
    p.status = 'pending';
    p.operation = (p.serverId == null) ? 'create' : 'update';
    p.updatedAt = DateTime.now().toIso8601String();

    if (isEditing) {
      await p.save();
    } else {
      await _parcelaBox.add(p);
    }

    await loadLocalParcelas();
    clearFormFields();
    if (_isOnline) await syncPending();
  }

  Future<void> deleteParcelaLocal(Parcela p) async {
    if (p.serverId == null) {
      await p.delete();
    } else {
      p.operation = 'delete';
      p.status = 'pending';
      await p.save();
    }
    await loadLocalParcelas();
    if (_isOnline) await syncPending();
  }

  void startEditParcelaObj(Parcela p) {
    setState(() {
      isEditing = true;
      editingParcela = p;
      _nombreController.text = p.nombre;
      _areaController.text = p.area?.toString() ?? '';
      _tipoCultivoController.text = p.tipoCultivoNombre ?? '';
      _selectedTipoCultivoId = p.idTipoCultivo;
      _selectedMunicipioId = p.idMunicipio;

      final municipio = _municipiosBox.get(p.idMunicipio?.toString());
      _municipioController.text = municipio != null ? municipio['nombre'] : '';

      _latitudController.text = p.latitud?.toString() ?? '';
      _longitudController.text = p.longitud?.toString() ?? '';
      _altitudController.text = p.altitud?.toString() ?? '';

      _vigente = p.vigente;
      _fechaRegistro = p.fechaRegistroIso != null
          ? DateTime.tryParse(p.fechaRegistroIso!)
          : null;
      showForm = true;
    });
  }

  Future<void> _pickCatalog({
    required String title,
    required Box catalogBox,
    required String idField,
    required String nameField,
    required Function(Map<String, dynamic>) onSelected,
  }) async {
    final items = catalogBox.values.cast<Map>().toList();
    items.sort(
      (a, b) => (a[nameField] as String).compareTo(b[nameField] as String),
    );

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(items[index]);
                  return ListTile(
                    title: Text(item[nameField] ?? ''),
                    onTap: () => Navigator.of(ctx).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }

  Future<void> _pickTipoCultivo() async {
    await _pickCatalog(
      title: 'Seleccionar Cultivo',
      catalogBox: _tipoCultivoBox,
      idField: 'id',
      nameField: 'cultivo',
      onSelected: (selected) {
        setState(() {
          _selectedTipoCultivoId = _toNullableInt(selected['id']);
          _tipoCultivoController.text = selected['cultivo'] ?? '';
        });
      },
    );
  }

  Future<void> _pickMunicipio() async {
    await _pickCatalog(
      title: 'Seleccionar Municipio',
      catalogBox: _municipiosBox,
      idField: 'id_municipio',
      nameField: 'nombre',
      onSelected: (selected) {
        setState(() {
          _selectedMunicipioId = _toNullableInt(selected['id_municipio']);
          _municipioController.text = selected['nombre'] ?? '';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final natureGreen = const Color(0xFF6DB571);
    final backgroundNature = const Color(0xFFEAFBE7);
    final accentNature = const Color(0xFFB2D8B2);

    return Scaffold(
      backgroundColor: backgroundNature,
      appBar: AppBar(
        backgroundColor: natureGreen,
        title: Text(
          'Parcelas - ${widget.nombreProductor}',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.sync,
              color: _isOnline ? Colors.white : Colors.white54,
            ),
            onPressed: manualRefresh,
            tooltip: _isOnline ? 'Actualizar' : 'Recargar datos locales',
          ),
        ],
      ),
      floatingActionButton: (showForm || widget.productorId == 0)
          ? null
          : FloatingActionButton(
              backgroundColor: natureGreen,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () => setState(() => showForm = true),
              tooltip: 'Agregar Parcela',
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: manualRefresh,
              child: ListView(
                padding: const EdgeInsets.all(12.0),
                children: [
                  if (showForm)
                    _buildForm(natureGreen, accentNature)
                  else
                    _buildList(natureGreen, accentNature),
                ],
              ),
            ),
    );
  }

  Widget _buildList(Color natureGreen, Color accentNature) {
    return Column(
      children: [
        Center(
          child: CircleAvatar(
            radius: 60,
            backgroundImage: const AssetImage('assets/images/primavera.png'),
            backgroundColor: Colors.transparent,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Buscar por nombre o cultivo',
            prefixIcon: Icon(Icons.search, color: natureGreen),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        if (filteredParcelas.isEmpty && !loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No se encontraron parcelas para este productor.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ...filteredParcelas.map((p) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: accentNature,
                  child: Icon(Icons.landscape, color: natureGreen),
                ),
                title: Text(
                  p.nombre,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    color: natureGreen,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.tipoCultivoNombre != null) Text(p.tipoCultivoNombre!),
                    if (p.area != null) Text('${p.area} cuerdas'),
                    if (p.status == 'pending')
                      const Row(
                        children: [
                          Icon(
                            Icons.sync_problem,
                            color: Colors.orange,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Pendiente',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      startEditParcelaObj(p);
                    } else if (value == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirmar eliminación'),
                          content: Text('¿Eliminar la parcela "${p.nombre}"?'),
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
                      if (confirmed == true) {
                        await deleteParcelaLocal(p);
                      }
                    } else if (value == 'visita') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FormularioVisita(
                            parcelaId: p.serverId.toString(),
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    //const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: natureGreen),
                          const SizedBox(width: 8),
                          Text(
                            'Editar',
                            style: GoogleFonts.montserrat(color: natureGreen),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'visita',
                      child: Row(
                        children: [
                          Icon(Icons.add_location, color: natureGreen),
                          const SizedBox(width: 8),
                          Text(
                            'Nueva Visita',
                            style: GoogleFonts.montserrat(color: natureGreen),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Eliminar',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildForm(Color natureGreen, Color accentNature) {
    return Card(
      elevation: 2,
      color: accentNature,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text(
                isEditing ? 'Editar Parcela' : 'Nueva Parcela',
                style: GoogleFonts.montserrat(
                  color: natureGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(
                    Icons.landscape,
                    color: Colors.green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                validator: (v) =>
                    (v?.isEmpty ?? true) ? 'Ingrese un nombre' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _areaController,
                decoration: const InputDecoration(
                  labelText: 'Área (cuerdas)',
                  prefixIcon: Icon(
                    Icons.square_foot,
                    color: Colors.green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (_toNullableDouble(v) == null)
                    ? 'Ingrese un área válida'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _latitudController,
                decoration: const InputDecoration(
                  labelText: 'Latitud',
                  prefixIcon: Icon(
                    Icons.location_on,
                    color: Colors.green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (_toNullableDouble(v) == null)
                    ? 'Ingrese una latitud válida'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _longitudController,
                decoration: const InputDecoration(
                  labelText: 'Longitud',
                  prefixIcon: Icon(
                    Icons.location_on,
                    color: Colors.green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (_toNullableDouble(v) == null)
                    ? 'Ingrese una longitud válida'
                    : null,
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _altitudController,
                decoration: const InputDecoration(
                  labelText: 'Altitud (msnm)',
                  prefixIcon: Icon(Icons.height, color: Colors.green, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (_toNullableDouble(v) == null)
                    ? 'Ingrese una altitud válida'
                    : null,
              ),

              const SizedBox(height: 8),
              TextFormField(
                controller: _tipoCultivoController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Cultivo',
                  prefixIcon: Icon(Icons.grass, color: Colors.green, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                onTap: _pickTipoCultivo,
                validator: (v) =>
                    (v?.isEmpty ?? true) ? 'Seleccione un cultivo' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _municipioController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  prefixIcon: Icon(
                    Icons.location_city,
                    color: Colors.green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
                onTap: _pickMunicipio,
                validator: (v) =>
                    (v?.isEmpty ?? true) ? 'Seleccione un municipio' : null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.cancel,
                        color: Colors.white,
                        size: 20,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 18,
                        ),
                      ),
                      label: Text(
                        'Cancelar',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: clearFormFields,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(
                        isEditing ? Icons.edit : Icons.add_circle_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEditing
                            ? Colors.orange
                            : natureGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 18,
                        ),
                      ),
                      label: Text(
                        isEditing ? 'Guardar' : 'Agregar',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: addOrUpdateParcela,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
