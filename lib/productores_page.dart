import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'parcelas_page.dart';

// MODELO Hive + ADAPTER MANUAL (no codegen) --------------------------------
@HiveType(typeId: 0)
class Productor extends HiveObject {
  @HiveField(0)
  int? serverId; // id_productor en Supabase

  @HiveField(1)
  String nombre;

  @HiveField(2)
  String? email;

  @HiveField(3)
  String? telefono;

  @HiveField(4)
  String? cui;

  @HiveField(5)
  String? operation; // 'create' | 'update' | 'delete' | null

  @HiveField(6)
  String status; // 'pending' | 'synced'

  @HiveField(7)
  String updatedAt;

  Productor({
    this.serverId,
    required this.nombre,
    this.email,
    this.telefono,
    this.cui,
    this.operation,
    this.status = 'pending',
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
    'id_productor': serverId,
    'nombre': nombre,
    'email': email,
    'telefono': telefono,
    'cui': cui,
    'operation': operation,
    'status': status,
    'updatedAt': updatedAt,
  };
}

class ProductorAdapter extends TypeAdapter<Productor> {
  @override
  final int typeId = 0;

  @override
  Productor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte() as int;
      final value = reader.read();
      fields[key] = value;
    }
    final serverIdRaw = fields[0];
    int? serverId;
    if (serverIdRaw is int)
      serverId = serverIdRaw;
    else if (serverIdRaw is num)
      serverId = serverIdRaw.toInt();
    else
      serverId = int.tryParse(serverIdRaw?.toString() ?? '');
    return Productor(
      serverId: serverId,
      nombre: fields[1] as String,
      email: fields[2] as String?,
      telefono: fields[3] as String?,
      cui: fields[4] as String?,
      operation: fields[5] as String?,
      status: fields[6] as String? ?? 'pending',
      updatedAt: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Productor obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.serverId)
      ..writeByte(1)
      ..write(obj.nombre)
      ..writeByte(2)
      ..write(obj.email)
      ..writeByte(3)
      ..write(obj.telefono)
      ..writeByte(4)
      ..write(obj.cui)
      ..writeByte(5)
      ..write(obj.operation)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.updatedAt);
  }
}
// ---------------------------------------------------------------------------

class ProductoresPage extends StatefulWidget {
  const ProductoresPage({super.key});

  @override
  State<ProductoresPage> createState() => _ProductoresPageState();
}

class _ProductoresPageState extends State<ProductoresPage>
    with SingleTickerProviderStateMixin {
  List<Productor> productores = [];
  List<Productor> filteredProductores = [];
  bool loading = false;

  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _cuiController = TextEditingController();
  final _searchController = TextEditingController();

  late AnimationController _animationController;

  bool isEditing = false;
  Productor? editingProductor;
  bool showForm = false;

  late Box<Productor> _box;

  late StreamSubscription<dynamic> _connectivitySub;
  dynamic _lastConnectivity;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _searchController.addListener(() {
      filterProductores(_searchController.text);
    });

    _initBoxAndLoad();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _cuiController.dispose();
    _searchController.dispose();
    _connectivitySub.cancel();
    super.dispose();
  }

  void clearFormFields() {
    setState(() {
      _nombreController.clear();
      _emailController.clear();
      _telephoneController.clear();
      _cuiController.clear();
      isEditing = false;
      editingProductor = null;
      showForm = false;
    });
  }

  void filterProductores(String query) {
    final search = query.toLowerCase();
    // No llames a setState aquí, deja que loadLocalProductores lo controle
    filteredProductores = productores.where((p) {
      final nombre = (p.nombre).toLowerCase();
      final cui = (p.cui ?? '').toLowerCase();
      return nombre.contains(search) || cui.contains(search);
    }).toList();
  }

  Future<void> loadLocalProductores() async {
    final List<Productor> allProductores = _box.values.toList();
    productores = allProductores.where((p) => p.operation != 'delete').toList();

    // Filtra y luego actualiza la UI en un solo paso
    setState(() {
      filterProductores(_searchController.text);
    });
  }

  Future<void> addProductor() async {
    final p = Productor(
      serverId: null,
      nombre: _nombreController.text,
      email: _emailController.text.isEmpty ? null : _emailController.text,
      telefono: _telephoneController.text.isEmpty
          ? null
          : _telephoneController.text,
      cui: _cuiController.text.isEmpty ? null : _cuiController.text,
      operation: 'create',
      status: 'pending',
    );
    await _box.add(p);
    await loadLocalProductores();
    clearFormFields();

    if (_isOnline) {
      await syncPending();
    }
  }

  Future<void> updateProductorLocal(
    Productor p,
    String nombre,
    String email,
    String telefono,
    String cui,
  ) async {
    p.nombre = nombre;
    p.email = email.isEmpty ? null : email;
    p.telefono = telefono.isEmpty ? null : telefono;
    p.cui = cui.isEmpty ? null : cui;
    if (p.serverId == null) {
      p.operation = 'create';
    } else {
      p.operation = 'update';
    }
    p.status = 'pending';
    p.updatedAt = DateTime.now().toIso8601String();
    await p.save();

    await loadLocalProductores();
    clearFormFields();

    if (_isOnline) {
      await syncPending();
    }
  }

  Future<void> deleteProductorLocal(Productor p) async {
    if (p.serverId == null) {
      await p.delete();
    } else {
      p.operation = 'delete';
      p.status = 'pending';
      p.updatedAt = DateTime.now().toIso8601String();
      await p.save();
    }

    await loadLocalProductores();

    if (_isOnline) {
      await syncPending();
    }
  }

  void startEditProductor(Productor productor) {
    setState(() {
      isEditing = true;
      editingProductor = productor;
      _nombreController.text = productor.nombre;
      _emailController.text = productor.email ?? '';
      _telephoneController.text = productor.telefono ?? '';
      _cuiController.text = productor.cui ?? '';
      showForm = true;
    });
  }

  void startAddProductor() {
    clearFormFields();
    setState(() {
      showForm = true;
    });
  }

  Future<void> syncPending() async {
    if (!_isOnline) return;

    final supabase = Supabase.instance.client;
    final pending = _box.values.where((p) => p.status == 'pending').toList();

    for (final p in pending) {
      final op = p.operation;
      try {
        if (op == 'create') {
          final insertMap = {
            'nombre': p.nombre,
            'email': p.email,
            'telefono': p.telefono,
            'cui': p.cui,
          };
          final res = await supabase
              .from('productores')
              .insert(insertMap)
              .select()
              .single();

          p.serverId = res['id_productor'];
          p.operation = null;
          p.status = 'synced';
          await p.save();
        } else if (op == 'update') {
          final serverId = p.serverId;
          if (serverId != null) {
            await supabase
                .from('productores')
                .update({
                  'nombre': p.nombre,
                  'email': p.email,
                  'telefono': p.telefono,
                  'cui': p.cui,
                })
                .eq('id_productor', serverId);
            p.operation = null;
            p.status = 'synced';
            await p.save();
          } else {
            p.operation = 'create';
            await p.save();
          }
        } else if (op == 'delete') {
          final serverId = p.serverId;
          if (serverId != null) {
            await supabase
                .from('productores')
                .delete()
                .eq('id_productor', serverId);
          }
          await p.delete();
        } else {
          p.status = 'synced';
          p.operation = null;
          await p.save();
        }
      } catch (e, st) {
        debugPrint(
          'Error sincronizando registro local key=${p.key} op=$op: $e',
        );
        debugPrint('$st');
      }
    }

    await loadLocalProductores();
  }

  Future<void> _initBoxAndLoad() async {
    try {
      if (!Hive.isAdapterRegistered(ProductorAdapter().typeId)) {
        Hive.registerAdapter(ProductorAdapter());
      }
    } catch (_) {}

    if (!Hive.isBoxOpen('productores')) {
      await Hive.openBox<Productor>('productores');
    }
    _box = Hive.box<Productor>('productores');

    await loadLocalProductores();

    final conn = Connectivity();
    _lastConnectivity = await conn.checkConnectivity();
    _isOnline =
        _normalizeConnectivity(_lastConnectivity) != ConnectivityResult.none;
    setState(() {});

    _connectivitySub = conn.onConnectivityChanged.listen((result) async {
      final now = _normalizeConnectivity(result);
      setState(() {
        _isOnline = now != ConnectivityResult.none;
      });

      if (_isOnline) {
        await manualRefresh();
      }
      _lastConnectivity = result;
    });

    if (_isOnline) {
      await manualRefresh();
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

  Future<void> fetchProductores() async {
    if (!_isOnline) {
      await loadLocalProductores();
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final result = await supabase.from('productores').select();
      final List<dynamic> remote = (result is List) ? result : [];

      final localByServerId = <int, Productor>{};
      for (final p in _box.values) {
        if (p.serverId != null) localByServerId[p.serverId!] = p;
      }

      for (final r in remote) {
        if (r is! Map) continue;
        final rawId = r['id_productor'] ?? r['id'];
        final serverId = (rawId is int)
            ? rawId
            : int.tryParse(rawId?.toString() ?? '');
        if (serverId == null) continue;

        final nombre = (r['nombre'] ?? '').toString();
        final email = r['email']?.toString();
        final telefono = r['telefono']?.toString();
        final cui = r['cui']?.toString();

        if (localByServerId.containsKey(serverId)) {
          final local = localByServerId[serverId]!;
          if (local.operation == null) {
            local.nombre = nombre;
            local.email = email;
            local.telefono = telefono;
            local.cui = cui;
            local.status = 'synced';
            await local.save();
          }
        } else {
          final np = Productor(
            serverId: serverId,
            nombre: nombre,
            email: email,
            telefono: telefono,
            cui: cui,
            status: 'synced',
            operation: null,
          );
          await _box.add(np);
        }
      }
    } catch (e, st) {
      debugPrint('Error fetchProductores: $e');
      debugPrint('$st');
    } finally {
      await loadLocalProductores();
    }
  }

  Future<void> manualRefresh() async {
    setState(() => loading = true);
    if (_isOnline) {
      await syncPending();
      await fetchProductores();
    } else {
      await loadLocalProductores();
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
        ),
      );
    }
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
          'Productores',
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
            tooltip: _isOnline ? 'Actualizar datos' : 'Sin conexión',
            onPressed: manualRefresh,
          ),
        ],
      ),
      floatingActionButton: showForm
          ? null
          : FloatingActionButton(
              backgroundColor: natureGreen,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: startAddProductor,
              tooltip: 'Agregar Productor',
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: manualRefresh,
              child: ListView(
                padding: const EdgeInsets.all(12.0),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: const AssetImage(
                        'assets/images/productores_header.png',
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar por CUI o Nombre',
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
                        child: Column(
                          children: [
                            Text(
                              isEditing
                                  ? 'Editar Productor'
                                  : 'Nuevo Productor',
                              style: GoogleFonts.montserrat(
                                color: natureGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon: Icon(
                                  Icons.person,
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
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(
                                  Icons.email,
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
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _telephoneController,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                prefixIcon: Icon(
                                  Icons.phone,
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
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _cuiController,
                              decoration: const InputDecoration(
                                labelText: 'CUI',
                                prefixIcon: Icon(
                                  Icons.badge,
                                  color: Colors.green,
                                  size: 15,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                              ),
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
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 18,
                                      ),
                                    ),
                                    label: Text(
                                      isEditing
                                          ? 'Guardar edición'
                                          : 'Agregar Productor',
                                      style: GoogleFonts.montserrat(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () {
                                      if (isEditing &&
                                          editingProductor != null) {
                                        updateProductorLocal(
                                          editingProductor!,
                                          _nombreController.text,
                                          _emailController.text,
                                          _telephoneController.text,
                                          _cuiController.text,
                                        );
                                      } else {
                                        addProductor();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: Icon(
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
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Column(
                        children: [
                          ...filteredProductores.asMap().entries.map((entry) {
                            final i = entry.key;
                            final productor = entry.value;
                            return FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _animationController,
                                curve: Interval(
                                  i /
                                      (filteredProductores.isEmpty
                                          ? 1
                                          : filteredProductores.length),
                                  1.0,
                                  curve: Curves.easeIn,
                                ),
                              ),
                              child: Card(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                elevation: 1,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: accentNature,
                                    child: Icon(
                                      Icons.person,
                                      color: natureGreen,
                                    ),
                                  ),
                                  title: Text(
                                    productor.nombre,
                                    style: GoogleFonts.montserrat(
                                      color: natureGreen,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.email,
                                            size: 16,
                                            color: Colors.green[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            productor.email ?? '',
                                            style: GoogleFonts.montserrat(
                                              color: Colors.green[800],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.badge,
                                            size: 16,
                                            color: Colors.green[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            productor.cui ?? '',
                                            style: GoogleFonts.montserrat(
                                              color: Colors.green[800],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if ((productor.status) == 'pending')
                                        Row(
                                          children: [
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.sync,
                                              size: 14,
                                              color: Colors.orange,
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
                                        ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: natureGreen,
                                    ),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        startEditProductor(productor);
                                      } else if (value == 'delete') {
                                        deleteProductorLocal(productor);
                                      } else if (value == 'parcelas') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ParcelasPage(
                                              productorId:
                                                  productor.serverId ?? 0,
                                              nombreProductor: productor.nombre,
                                            ),
                                          ),
                                        );
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
                                            const SizedBox(width: 8),
                                            Text(
                                              'Editar',
                                              style: GoogleFonts.montserrat(
                                                color: natureGreen,
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
                                            const SizedBox(width: 8),
                                            Text(
                                              'Eliminar',
                                              style: GoogleFonts.montserrat(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'parcelas',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.landscape,
                                              color: natureGreen,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Ver Parcelas',
                                              style: GoogleFonts.montserrat(
                                                color: natureGreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          if (filteredProductores.isEmpty && !loading)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No se encontraron productores.',
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
