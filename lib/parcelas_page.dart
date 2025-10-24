import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'visita_parcela.dart';

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

// MODELO Hive: Parcela -------------------------------------------------------
@HiveType(typeId: 10)
class Parcela extends HiveObject {
  @HiveField(0)
  int? serverId; // id_parcela en Supabase

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
  String? operation; // 'create' | 'update' | 'delete' | null

  @HiveField(12)
  String status; // 'pending' | 'synced'

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

// Adapter manual para Parcela (read/write seguros)
class ParcelaAdapter extends TypeAdapter<Parcela> {
  @override
  final int typeId = 10;

  @override
  Parcela read(BinaryReader reader) {
    final n = reader.readByte();
    final m = <int, dynamic>{};
    for (var i = 0; i < n; i++) {
      final key = reader.readByte() as int;
      final val = reader.read();
      m[key] = val;
    }

    final serverId = _toNullableInt(m[0]);
    final nombre = (m[1] ?? '').toString();
    final area = _toNullableDouble(m[2]);
    final tipoCultivoNombre = m[3] as String?;
    final idTipoCultivo = _toNullableInt(m[4]);
    final latitud = _toNullableDouble(m[5]);
    final longitud = _toNullableDouble(m[6]);
    final altitud = _toNullableDouble(m[7]);
    final idMunicipio = _toNullableInt(m[8]);
    final vigente = m[9] as bool? ?? true;
    final fechaRegistroIso = m[10] as String?;
    final operation = m[11] as String?;
    final status = (m[12] as String?) ?? 'pending';
    final updatedAt = m[13] as String?;
    final productorId = _toNullableInt(m[14]);

    return Parcela(
      serverId: serverId,
      nombre: nombre,
      area: area,
      tipoCultivoNombre: tipoCultivoNombre,
      idTipoCultivo: idTipoCultivo,
      latitud: latitud,
      longitud: longitud,
      altitud: altitud,
      idMunicipio: idMunicipio,
      vigente: vigente,
      fechaRegistroIso: fechaRegistroIso,
      operation: operation,
      status: status,
      updatedAt: updatedAt,
      productorId: productorId,
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
// ---------------------------------------------------------------------------

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
  final _idParcelaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _areaController = TextEditingController();
  final _tipoCultivoController = TextEditingController();
  final _idTipoCultivoController = TextEditingController();
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  final _altitudController = TextEditingController();
  final _idMunicipioController = TextEditingController();
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
  late Box _departamentosBox;

  late StreamSubscription<dynamic> _connectivitySub;
  dynamic _lastConnectivity;
  bool _isOnline = false;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _searchController.addListener(() {
      filterParcelas(_searchController.text);
    });

    _openBoxesAndInit();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _idParcelaController.dispose();
    _nombreController.dispose();
    _areaController.dispose();
    _tipoCultivoController.dispose();
    _idTipoCultivoController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    _altitudController.dispose();
    _idMunicipioController.dispose();
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

    _parcelaBox = Hive.box<Parcela>('parcelas');
    _tipoCultivoBox = Hive.box('catalog_tipo_cultivo');
    _municipiosBox = Hive.box('catalog_municipios');
    _departamentosBox = Hive.box('catalog_departamentos');

    await loadLocalParcelas();

    final conn = Connectivity();
    _lastConnectivity = await conn.checkConnectivity();
    _isOnline =
        _normalizeConnectivity(_lastConnectivity) != ConnectivityResult.none;
    setState(() {});

    _connectivitySub = conn.onConnectivityChanged.listen((result) async {
      final prev = _normalizeConnectivity(_lastConnectivity);
      final now = _normalizeConnectivity(result);

      final wasOnline = _isOnline;
      _isOnline = now != ConnectivityResult.none;
      if (wasOnline != _isOnline) setState(() {});

      if (prev == ConnectivityResult.none && now != ConnectivityResult.none) {
        await syncPending();
        await _syncCatalogsFromServer();
        await fetchParcelas();
      }
      _lastConnectivity = result;
    });

    if (_isOnline) {
      await syncPending();
      await _syncCatalogsFromServer();
      await fetchParcelas();
    }
  }

  ConnectivityResult _normalizeConnectivity(dynamic value) {
    try {
      if (value == null) return ConnectivityResult.none;
      if (value is ConnectivityResult) return value;
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is ConnectivityResult) return first;
        if (first is String) {
          final s = first.toLowerCase();
          if (s.contains('wifi')) return ConnectivityResult.wifi;
          if (s.contains('mobile') || s.contains('cellular'))
            return ConnectivityResult.mobile;
        }
      }
    } catch (_) {}
    return ConnectivityResult.none;
  }

  Future<void> _syncCatalogsFromServer() async {
    if (_normalizeConnectivity(await Connectivity().checkConnectivity()) ==
        ConnectivityResult.none)
      return;

    try {
      final supabase = Supabase.instance.client;
      final resTipo = await supabase.from('tipo_cultivo').select();
      if (resTipo is List) {
        await _tipoCultivoBox.clear();
        for (final e in resTipo) {
          if (e is Map) {
            final id = e['id'] ?? e['id_tipo'] ?? e['id_cultivo'];
            if (id != null)
              _tipoCultivoBox.put(id.toString(), Map<String, dynamic>.from(e));
          }
        }
      }
      final resDeps = await supabase.from('departamentos').select();
      if (resDeps is List) {
        await _departamentosBox.clear();
        for (final e in resDeps) {
          if (e is Map) {
            final id = e['id'] ?? e['id_departamento'];
            if (id != null)
              _departamentosBox.put(
                id.toString(),
                Map<String, dynamic>.from(e),
              );
          }
        }
      }
      final resMun = await supabase.from('municipios').select();
      if (resMun is List) {
        await _municipiosBox.clear();
        for (final e in resMun) {
          if (e is Map) {
            final id = e['id_municipio'] ?? e['id'];
            if (id != null)
              _municipiosBox.put(id.toString(), Map<String, dynamic>.from(e));
          }
        }
      }
    } catch (e, st) {
      debugPrint('Error sincronizando catálogos: $e');
      debugPrint('$st');
    }
  }

  Future<void> syncPending() async {
    final online =
        _normalizeConnectivity(await Connectivity().checkConnectivity()) !=
        ConnectivityResult.none;
    if (!online) return;

    final supabase = Supabase.instance.client;
    final pending = _parcelaBox.values
        .where((p) => p.status == 'pending')
        .toList();

    for (final p in pending) {
      final op = p.operation;
      try {
        if (op == 'create') {
          final insertMap = {
            'nombre': p.nombre,
            'area': p.area,
            // 'tipo_cultivo': p.tipoCultivoNombre, // QUITADO, SOLO ID
            'id_tipo_cultivo': p.idTipoCultivo,
            'latitud': p.latitud,
            'longitud': p.longitud,
            'altitud': p.altitud,
            'id_municipio': p.idMunicipio,
            'id_productor': p.productorId ?? widget.productorId,
            'fecha_registro': p.fechaRegistroIso,
            'vigente': p.vigente,
          };
          dynamic res = await supabase
              .from('parcelas')
              .insert(insertMap)
              .select();
          dynamic server;
          if (res is List && res.isNotEmpty)
            server = res.first;
          else if (res is Map)
            server = res;
          else
            server = null;
          final serverId = server != null
              ? (server['id_parcela'] ?? server['id'])
              : null;
          if (serverId != null) {
            p.serverId = (serverId is int)
                ? serverId
                : int.tryParse(serverId.toString());
            p.operation = null;
            p.status = 'synced';
            await p.save();
          }
        } else if (op == 'update') {
          final sid = p.serverId;
          if (sid != null) {
            await supabase
                .from('parcelas')
                .update({
                  'nombre': p.nombre,
                  'area': p.area,
                  // 'tipo_cultivo': p.tipoCultivoNombre, // QUITADO, SOLO ID
                  'id_tipo_cultivo': p.idTipoCultivo,
                  'latitud': p.latitud,
                  'longitud': p.longitud,
                  'altitud': p.altitud,
                  'id_municipio': p.idMunicipio,
                  'vigente': p.vigente,
                })
                .eq('id_parcela', sid);
            p.operation = null;
            p.status = 'synced';
            await p.save();
          } else {
            p.operation = 'create';
            await p.save();
          }
        } else if (op == 'delete') {
          final sid = p.serverId;
          if (sid != null) {
            await supabase.from('parcelas').delete().eq('id_parcela', sid);
          }
          await p.delete();
        } else {
          p.status = 'synced';
          p.operation = null;
          await p.save();
        }
      } catch (e, st) {
        debugPrint('Error sincronizando parcela serverId=${p.serverId}: $e');
        debugPrint('$st');
      }
    }

    await loadLocalParcelas();
  }

  Future<void> fetchParcelas() async {
    setState(() => loading = true);
    final online =
        _normalizeConnectivity(await Connectivity().checkConnectivity()) !=
        ConnectivityResult.none;
    if (!online) {
      await loadLocalParcelas();
      setState(() {
        loading = false;
        _animation_controller_forward_safe();
      });
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final result = await supabase
          .from('parcelas')
          .select()
          .eq('id_productor', widget.productorId);

      final List<dynamic> remote = result ?? [];

      final localByServerId = <int, Parcela>{};
      for (final p in _parcelaBox.values) {
        if (p.serverId != null) localByServerId[p.serverId!] = p;
      }

      for (final r in remote) {
        if (r is! Map) continue;
        final serverId = _toNullableInt(r['id_parcela'] ?? r['id']);
        if (serverId == null) continue;
        final nombre = (r['nombre'] ?? '').toString();
        final area = _toNullableDouble(r['area']);
        final tipoNombre = r['tipo_cultivo'] ?? r['cultivo'];
        final idTipo = _toNullableInt(r['id_tipo_cultivo']);
        final lat = _toNullableDouble(r['latitud']);
        final lng = _toNullableDouble(r['longitud']);
        final alt = _toNullableDouble(r['altitud']);
        final idMun = _toNullableInt(r['id_municipio']);
        final vigente = r['vigente'] == null
            ? true
            : (r['vigente'] as bool? ?? true);
        final fechaIso = r['fecha_registro']?.toString();
        final productoIdRemote = _toNullableInt(r['id_productor']);

        if (localByServerId.containsKey(serverId)) {
          final local = localByServerId[serverId]!;
          if (local.operation == null) {
            local.nombre = nombre;
            local.area = area;
            local.tipoCultivoNombre = tipoNombre?.toString();
            local.idTipoCultivo = idTipo;
            local.latitud = lat;
            local.longitud = lng;
            local.altitud = alt;
            local.idMunicipio = idMun;
            local.vigente = vigente;
            local.fechaRegistroIso = fechaIso;
            local.productorId = productoIdRemote;
            local.status = 'synced';
            await local.save();
          }
        } else {
          final newP = Parcela(
            serverId: serverId,
            nombre: nombre.toString(),
            area: area,
            tipoCultivoNombre: tipoNombre?.toString(),
            idTipoCultivo: idTipo,
            latitud: lat,
            longitud: lng,
            altitud: alt,
            idMunicipio: idMun,
            vigente: vigente,
            fechaRegistroIso: fechaIso,
            operation: null,
            status: 'synced',
            productorId: productoIdRemote,
          );
          await _parcelaBox.add(newP);
        }
      }

      await loadLocalParcelas();
    } catch (e, st) {
      debugPrint('Error fetchParcelas: $e');
      debugPrint('$st');
      await loadLocalParcelas();
    } finally {
      setState(() {
        loading = false;
        _animation_controller_forward_safe();
      });
    }
  }

  void _animation_controller_forward_safe() {
    try {
      _animationController.forward(from: 0);
    } catch (_) {}
  }

  Future<void> loadLocalParcelas() async {
    debugPrint('DEBUG: widget.productorId (pantalla): ${widget.productorId}');
    parcelas = _parcelaBox.values
        .where(
          (p) =>
              p.operation != 'delete' && (p.productorId == widget.productorId),
        )
        .toList();
    filteredParcelas = List<Parcela>.from(parcelas);

    setState(() {});
  }

  void filterParcelas(String query) {
    setState(() {
      final search = query.toLowerCase();
      filteredParcelas = parcelas.where((p) {
        final nombre = (p.nombre).toLowerCase();
        final tipoCultivo = (p.tipoCultivoNombre ?? '').toLowerCase();
        final area = (p.area?.toString() ?? '').toLowerCase();
        return nombre.contains(search) ||
            tipoCultivo.contains(search) ||
            area.contains(search);
      }).toList();
    });
  }

  void clearFormFields() {
    _idParcelaController.clear();
    _nombreController.clear();
    _areaController.clear();
    _tipoCultivoController.clear();
    _idTipoCultivoController.clear();
    _latitudController.clear();
    _longitudController.clear();
    _altitudController.clear();
    _idMunicipioController.clear();
    _vigente = true;
    _fechaRegistro = null;
    isEditing = false;
    editingParcela = null;
    _selectedTipoCultivoId = null;
    _selectedMunicipioId = null;
    setState(() {
      showForm = false;
    });
  }

  Future<void> addParcela() async {
    if (!_formKey.currentState!.validate()) return;
    final nowIso =
        _fechaRegistro?.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String();

    final p = Parcela(
      serverId: null,
      nombre: _nombreController.text,
      area: double.tryParse(_areaController.text.replaceAll(',', '.')),
      tipoCultivoNombre: _tipoCultivoController.text.isEmpty
          ? null
          : _tipoCultivoController.text,
      idTipoCultivo:
          _selectedTipoCultivoId ?? int.tryParse(_idTipoCultivoController.text),
      latitud: double.tryParse(_latitudController.text.replaceAll(',', '.')),
      longitud: double.tryParse(_longitudController.text.replaceAll(',', '.')),
      altitud: double.tryParse(_altitudController.text.replaceAll(',', '.')),
      idMunicipio:
          _selectedMunicipioId ?? int.tryParse(_idMunicipioController.text),
      vigente: _vigente,
      fechaRegistroIso: nowIso,
      operation: 'create',
      status: 'pending',
      productorId: widget.productorId,
    );

    await _parcelaBox.add(p);
    await loadLocalParcelas();
    clearFormFields();

    if (_isOnline) {
      await syncPending();
      await fetchParcelas();
    }
  }

  Future<void> updateParcela() async {
    if (!isEditing || editingParcela == null) return;
    if (!_formKey.currentState!.validate()) return;

    final p = editingParcela!;
    p.nombre = _nombreController.text;
    p.area = double.tryParse(_areaController.text.replaceAll(',', '.'));
    p.tipoCultivoNombre = _tipoCultivoController.text.isEmpty
        ? null
        : _tipoCultivoController.text;
    p.idTipoCultivo =
        _selectedTipoCultivoId ?? int.tryParse(_idTipoCultivoController.text);
    p.latitud = double.tryParse(_latitudController.text.replaceAll(',', '.'));
    p.longitud = double.tryParse(_longitudController.text.replaceAll(',', '.'));
    p.altitud = double.tryParse(_altitudController.text.replaceAll(',', '.'));
    p.idMunicipio =
        _selectedMunicipioId ?? int.tryParse(_idMunicipioController.text);
    p.vigente = _vigente;
    p.updatedAt = DateTime.now().toIso8601String();

    if (p.serverId == null) {
      p.operation = 'create';
    } else {
      p.operation = 'update';
    }
    p.status = 'pending';
    await p.save();

    await loadLocalParcelas();
    clearFormFields();

    if (_isOnline) {
      await syncPending();
      await fetchParcelas();
    }
  }

  Future<void> deleteParcelaLocal(Parcela p) async {
    if (p.serverId == null) {
      await p.delete();
    } else {
      p.operation = 'delete';
      p.status = 'pending';
      p.updatedAt = DateTime.now().toIso8601String();
      await p.save();
    }
    await loadLocalParcelas();

    if (_isOnline) {
      await syncPending();
      await fetchParcelas();
    }
  }

  void startEditParcelaObj(Parcela p) {
    setState(() {
      isEditing = true;
      editingParcela = p;
      _idParcelaController.text = p.serverId?.toString() ?? '';
      _nombreController.text = p.nombre;
      _areaController.text = p.area?.toString() ?? '';
      _tipoCultivoController.text = p.tipoCultivoNombre ?? '';
      _idTipoCultivoController.text = p.idTipoCultivo?.toString() ?? '';
      _latitudController.text = p.latitud?.toString() ?? '';
      _longitudController.text = p.longitud?.toString() ?? '';
      _altitudController.text = p.altitud?.toString() ?? '';
      _idMunicipioController.text = p.idMunicipio?.toString() ?? '';
      _vigente = p.vigente;
      try {
        _fechaRegistro = p.fechaRegistroIso != null
            ? DateTime.parse(p.fechaRegistroIso!).toLocal()
            : null;
      } catch (_) {
        _fechaRegistro = null;
      }
      showForm = true;
    });
  }

  // Picker helpers
  Future<void> _pickTipoCultivo() async {
    final online =
        _normalizeConnectivity(await Connectivity().checkConnectivity()) !=
        ConnectivityResult.none;
    List<Map<String, dynamic>> items = [];
    if (online) {
      final res = await Supabase.instance.client.from('tipo_cultivo').select();
      if (res is List) {
        items = res.map((e) => Map<String, dynamic>.from(e)).toList();
        await _tipoCultivoBox.clear();
        for (final i in items) {
          _tipoCultivoBox.put(i['id'].toString(), i);
        }
      }
    } else {
      items = _tipoCultivoBox.values.cast<Map<String, dynamic>>().toList();
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return ListView(
          children: items.map((itm) {
            return ListTile(
              title: Text(itm['cultivo'] ?? ''),
              onTap: () => Navigator.of(ctx).pop(itm),
            );
          }).toList(),
        );
      },
    );
    if (selected != null) {
      setState(() {
        _selectedTipoCultivoId = _toNullableInt(selected['id']);
        _tipoCultivoController.text = (selected['cultivo'] ?? '').toString();
      });
    }
  }

  Future<void> _pickMunicipio() async {
    final online =
        _normalizeConnectivity(await Connectivity().checkConnectivity()) !=
        ConnectivityResult.none;
    List<Map<String, dynamic>> items = [];
    if (online) {
      final res = await Supabase.instance.client.from('municipios').select();
      if (res is List) {
        items = res.map((e) => Map<String, dynamic>.from(e)).toList();
        await _municipiosBox.clear();
        for (final i in items) {
          _municipiosBox.put(i['id_municipio'].toString(), i);
        }
      }
    } else {
      items = _municipiosBox.values.cast<Map<String, dynamic>>().toList();
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return ListView(
          children: items.map((itm) {
            return ListTile(
              title: Text(itm['nombre'] ?? ''),
              onTap: () => Navigator.of(ctx).pop(itm),
            );
          }).toList(),
        );
      },
    );
    if (selected != null) {
      setState(() {
        _selectedMunicipioId = _toNullableInt(
          selected['id_municipio'] ?? selected['id'],
        );
        _idMunicipioController.text =
            (selected['nombre'] ?? selected['id_municipio']?.toString() ?? '')
                .toString();
      });
    }
  }

  Future<void> _pickFechaRegistro(BuildContext context) async {
    final initial = _fechaRegistro ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaRegistro = picked;
      });
    }
  }

  void _markParcelaRecentlyVisited(int parcelaId) {
    setState(() {
      _recentlyVisitedIds.add(parcelaId);
    });
    Timer(_highlightDuration, () {
      if (mounted) {
        setState(() {
          _recentlyVisitedIds.remove(parcelaId);
        });
      }
    });
  }

  Future<void> _manualRefresh() async {
    final now = _normalizeConnectivity(
      await Connectivity().checkConnectivity(),
    );
    if (now == ConnectivityResult.none) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No hay conexión.')));
      }
      return;
    }

    if (mounted) setState(() => loading = true);
    try {
      await syncPending();
      await _syncCatalogsFromServer();
      await fetchParcelas();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actualización completa.')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final natureGreen = const Color(0xFF6DB571);
    final backgroundNature = const Color(0xFFEAFBE7);
    final accentNature = const Color(0xFFB2D8B2);
    debugPrint(
      'DEBUG: build - longitud filteredParcelas = ${filteredParcelas.length}',
    );
    for (final p in filteredParcelas) {
      debugPrint(
        'DEBUG: build muestra -> ${p.nombre} (productorId=${p.productorId})',
      );
    }
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
            onPressed: _isOnline ? _manualRefresh : null,
            tooltip: _isOnline ? 'Actualizar' : 'Sin conexión',
          ),
        ],
      ),
      floatingActionButton: showForm
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
              onRefresh: () async {
                final now = _normalizeConnectivity(
                  await Connectivity().checkConnectivity(),
                );
                if (now == ConnectivityResult.none) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No hay conexión para actualizar.'),
                      ),
                    );
                  return;
                }
                await syncPending();
                await _syncCatalogsFromServer();
                await fetchParcelas();
              },
              child: ListView(
                padding: const EdgeInsets.all(12.0),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: const AssetImage(
                        'assets/images/primavera.png',
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar por nombre, cultivo o área',
                      prefixIcon: Icon(Icons.search, color: natureGreen),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (showForm)
                    Card(
                      elevation: 2,
                      color: accentNature,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _nombreController,
                                decoration: InputDecoration(
                                  labelText: 'Nombre',
                                  prefixIcon: const Icon(
                                    Icons.landscape,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                ),
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty) {
                                    return 'Ingrese nombre';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _areaController,
                                decoration: InputDecoration(
                                  labelText: 'Área (ha)',
                                  prefixIcon: const Icon(
                                    Icons.square_foot,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty) {
                                    return 'Ingrese el área';
                                  }
                                  final val = double.tryParse(
                                    v!.replaceAll(',', '.'),
                                  );
                                  if (val == null || val <= 0) {
                                    return 'Área inválida';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _tipoCultivoController,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: 'Tipo de Cultivo',
                                        prefixIcon: const Icon(
                                          Icons.grass,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 8,
                                            ),
                                      ),
                                      onTap: _pickTipoCultivo,
                                      validator: (v) {
                                        if ((v ?? '').trim().isEmpty) {
                                          return 'Seleccione tipo de cultivo';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onPressed: _pickTipoCultivo,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _idMunicipioController,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: 'Municipio',
                                        prefixIcon: const Icon(
                                          Icons.location_city,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 8,
                                            ),
                                      ),
                                      onTap: _pickMunicipio,
                                      validator: (v) {
                                        if ((v ?? '').trim().isEmpty) {
                                          return 'Seleccione municipio';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onPressed: _pickMunicipio,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _latitudController,
                                      decoration: InputDecoration(
                                        labelText: 'Latitud',
                                        prefixIcon: const Icon(
                                          Icons.pin_drop,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _longitudController,
                                      decoration: InputDecoration(
                                        labelText: 'Longitud',
                                        prefixIcon: const Icon(
                                          Icons.pin_drop,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _altitudController,
                                      decoration: InputDecoration(
                                        labelText: 'Altitud (msnm)',
                                        prefixIcon: const Icon(
                                          Icons.terrain,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: _vigente,
                                          onChanged: (val) {
                                            setState(() => _vigente = val!);
                                          },
                                        ),
                                        const Text('Vigente'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: Icon(
                                        isEditing
                                            ? Icons.edit
                                            : Icons.add_circle_outline,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isEditing
                                            ? Colors.orange
                                            : natureGreen,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 18,
                                        ),
                                      ),
                                      label: Text(
                                        isEditing
                                            ? 'Guardar edición'
                                            : 'Agregar Parcela',
                                        style: GoogleFonts.montserrat(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () {
                                        if (isEditing &&
                                            editingParcela != null) {
                                          updateParcela();
                                        } else {
                                          addParcela();
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Column(
                        children: [
                          ...filteredParcelas.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;
                            final parcelaId = p.serverId ?? 0;
                            final isHighlighted = _recentlyVisitedIds.contains(
                              parcelaId,
                            );
                            final cardColor = isHighlighted
                                ? accentNature
                                : Colors.white;
                            final scale = isHighlighted ? 1.02 : 1.0;
                            final elevation = isHighlighted ? 6.0 : 1.0;

                            return FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _animationController,
                                curve: Interval(
                                  i /
                                      (filteredParcelas.isEmpty
                                          ? 1
                                          : filteredParcelas.length),
                                  1.0,
                                  curve: Curves.easeIn,
                                ),
                              ),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 1.0, end: scale),
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutBack,
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    child: Stack(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 350,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Card(
                                            color: cardColor,
                                            margin: EdgeInsets.zero,
                                            elevation: elevation,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: ListTile(
                                              onTap: () async {
                                                final parcelaIdString =
                                                    (p.serverId ?? 0)
                                                        .toString();
                                                final result =
                                                    await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            FormularioVisita(
                                                              parcelaId:
                                                                  parcelaIdString,
                                                            ),
                                                      ),
                                                    );
                                                if (result == true) {
                                                  await fetchParcelas();
                                                  _markParcelaRecentlyVisited(
                                                    parcelaId,
                                                  );
                                                }
                                              },
                                              leading: CircleAvatar(
                                                backgroundColor: accentNature,
                                                child: Icon(
                                                  Icons.landscape,
                                                  color: natureGreen,
                                                ),
                                              ),
                                              title: Text(
                                                p.nombre,
                                                style: GoogleFonts.montserrat(
                                                  color: natureGreen,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if ((p.tipoCultivoNombre ??
                                                          '')
                                                      .isNotEmpty)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.grass,
                                                          size: 16,
                                                          color:
                                                              Colors.green[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          p.tipoCultivoNombre ??
                                                              '',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color: Colors
                                                                    .green[800],
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  if ((p.area?.toString() ?? '')
                                                      .isNotEmpty)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.square_foot,
                                                          size: 16,
                                                          color:
                                                              Colors.green[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          p.area?.toString() ??
                                                              '',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color: Colors
                                                                    .green[800],
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  if (p.status == 'pending')
                                                    Row(
                                                      children: [
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Icon(
                                                          Icons.sync,
                                                          size: 14,
                                                          color: Colors.orange,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          'Pendiente de sincronizar',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color: Colors
                                                                    .orange,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                              trailing: PopupMenuButton<String>(
                                                icon: Icon(
                                                  Icons.more_vert,
                                                  color: natureGreen,
                                                ),
                                                onSelected: (value) async {
                                                  if (value == 'edit') {
                                                    startEditParcelaObj(p);
                                                  } else if (value ==
                                                      'visita') {
                                                    final parcelaIdString =
                                                        (p.serverId ?? 0)
                                                            .toString();
                                                    final result =
                                                        await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                FormularioVisita(
                                                                  parcelaId:
                                                                      parcelaIdString,
                                                                ),
                                                          ),
                                                        );
                                                    if (result == true) {
                                                      await fetchParcelas();
                                                      _markParcelaRecentlyVisited(
                                                        parcelaId,
                                                      );
                                                    }
                                                  } else if (value ==
                                                      'delete') {
                                                    final confirmed = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Confirmar eliminación',
                                                        ),
                                                        content: Text(
                                                          '¿Eliminar la parcela "${p.nombre}"?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(false),
                                                            child: const Text(
                                                              'Cancelar',
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(true),
                                                            child: const Text(
                                                              'Eliminar',
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirmed == true) {
                                                      await deleteParcelaLocal(
                                                        p,
                                                      );
                                                    }
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.edit,
                                                          color: natureGreen,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'Editar',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color:
                                                                    natureGreen,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'visita',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .medical_services,
                                                          color: natureGreen,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'Registrar Visita',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color:
                                                                    natureGreen,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.delete,
                                                          color: Colors.red,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'Eliminar',
                                                          style:
                                                              GoogleFonts.montserrat(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: AnimatedOpacity(
                                            opacity: isHighlighted ? 1.0 : 0.0,
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.fiber_new,
                                                    size: 14,
                                                    color: Colors.white,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Nueva visita',
                                                    style:
                                                        GoogleFonts.montserrat(
                                                          fontSize: 12,
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          }).toList(),
                          if (filteredParcelas.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No se encontraron parcelas.',
                                style: GoogleFonts.montserrat(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
