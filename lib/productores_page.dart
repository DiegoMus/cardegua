import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'parcelas_page.dart';
import 'sync_service.dart';

// --- Modelo Hive + ADAPTER MANUAL (CORREGIDO) ---
@HiveType(typeId: 0)
class Productor extends HiveObject {
  @HiveField(0)
  int? serverId;
  @HiveField(1)
  String nombre;
  @HiveField(2)
  String? email;
  @HiveField(3)
  String? telefono;
  @HiveField(4)
  String? cui;
  @HiveField(5)
  String? operation;
  @HiveField(6)
  String status;
  @HiveField(7)
  String updatedAt;
  @HiveField(8)
  String uuid;

  Productor({
    this.serverId,
    required this.nombre,
    this.email,
    this.telefono,
    this.cui,
    this.operation,
    this.status = 'pending',
    String? updatedAt,
    String? uuid,
  }) : uuid = uuid ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  // Dentro de la clase Productor
  factory Productor.fromJson(Map<String, dynamic> json) {
    return Productor(
      serverId: json['id_productor'] as int?,
      uuid: json['uuid'] as String? ?? '', // <-- CORRECCIÓN
      nombre: json['nombre'] as String? ?? '', // <-- CORRECCIÓN
      cui: json['cui'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      status: 'synced',
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // No incluimos 'id_productor' (serverId) porque Supabase lo genera en la inserción.
      // Lo incluimos en la actualización, pero el `update` de Supabase lo ignora.
      'uuid': uuid,
      'nombre': nombre,
      'cui': cui,
      'telefono': telefono,
      'email': email,
    };
  }
}

class ProductorAdapter extends TypeAdapter<Productor> {
  @override
  final int typeId = 0;

  @override
  Productor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Productor(
      serverId: fields[0] as int?,
      nombre: fields[1] as String,
      email: fields[2] as String?,
      telefono: fields[3] as String?,
      cui: fields[4] as String?,
      operation: fields[5] as String?,
      status: fields[6] as String? ?? 'pending',
      updatedAt: fields[7] as String?,
      uuid: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Productor obj) {
    // CORRECCIÓN: El número de campos es 9 (del 0 al 8).
    writer
      ..writeByte(9)
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
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.uuid); // Ahora el UUID se guarda siempre.
  }
}

// --- PÁGINA DE PRODUCTORES ---
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

  // --- NUEVA FUNCIÓN CENTRALIZADA PARA GUARDAR Y SINCRONIZAR ---
  Future<void> _submitProductor() async {
    if (_nombreController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El nombre del productor es obligatorio.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 1. Mostrar diálogo de carga SI ESTAMOS ONLINE para bloquear la UI
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
              Text('Guardando productor...'),
            ],
          ),
        ),
      );
    }

    try {
      // 2. Crear o actualizar el productor en la base de datos local (Hive)
      if (isEditing && editingProductor != null) {
        final p = editingProductor!;
        p.nombre = _nombreController.text;
        p.email = _emailController.text.isEmpty ? null : _emailController.text;
        p.telefono = _telephoneController.text.isEmpty
            ? null
            : _telephoneController.text;
        p.cui = _cuiController.text.isEmpty ? null : _cuiController.text;
        p.operation = (p.serverId == null) ? 'create' : 'update';
        p.status = 'pending';
        p.updatedAt = DateTime.now().toIso8601String();
        await p.save();
      } else {
        final p = Productor(
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
      }

      // 3. Si estamos online, ESPERAR a que la sincronización termine.
      if (_isOnline) {
        await SyncService.syncAllPendingData();
      }
    } catch (e) {
      debugPrint("Error en _submitProductor: $e");
    } finally {
      // 4. Cerrar el diálogo de carga (si se mostró)
      if (_isOnline && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // 5. Limpiar el formulario y recargar la lista de la UI
    clearFormFields();
    await loadLocalProductores();
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
    setState(() {
      filteredProductores = productores.where((p) {
        final nombre = p.nombre.toLowerCase();
        final cui = (p.cui ?? '').toLowerCase();
        return nombre.contains(search) || cui.contains(search);
      }).toList();
    });
  }

  Future<void> loadLocalProductores() async {
    productores = _box.values.where((p) => p.operation != 'delete').toList();
    filterProductores(_searchController.text);
  }

  Future<void> deleteProductorLocal(Productor p) async {
    if (p.serverId == null) {
      await p.delete();
    } else {
      p.operation = 'delete';
      p.status = 'pending';
      await p.save();
    }
    await loadLocalProductores();
    if (_isOnline) {
      await SyncService.syncAllPendingData();
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
    final initialResult = await conn.checkConnectivity();
    _isOnline =
        initialResult.contains(ConnectivityResult.mobile) ||
        initialResult.contains(ConnectivityResult.wifi);
    setState(() {});

    _connectivitySub = conn.onConnectivityChanged.listen((result) async {
      final newStatus =
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.wifi);
      if (_isOnline != newStatus) {
        setState(() {
          _isOnline = newStatus;
        });
        if (newStatus) {
          await manualRefresh();
        }
      }
    });

    if (_isOnline) {
      await manualRefresh();
    }
  }

  Future<void> fetchProductores() async {
    if (!_isOnline) {
      await loadLocalProductores();
      return;
    }
    try {
      final result = await Supabase.instance.client
          .from('productores')
          .select();
      for (final r in result) {
        final serverId = r['id_productor'] as int?;
        final uuid = r['uuid'] as String?;
        if (serverId == null || uuid == null) continue;

        Productor? local;
        try {
          local = _box.values.firstWhere((p) => p.uuid == uuid);
        } catch (_) {}

        if (local == null) {
          final np = Productor(
            serverId: serverId,
            nombre: r['nombre'] ?? '',
            email: r['email'],
            telefono: r['telefono'],
            cui: r['cui'],
            status: 'synced',
            operation: null,
            uuid: uuid,
          );
          await _box.add(np);
        } else if (local.operation == null) {
          local.nombre = r['nombre'] ?? local.nombre;
          local.email = r['email'] ?? local.email;
          local.telefono = r['telefono'] ?? local.telefono;
          local.cui = r['cui'] ?? local.cui;
          local.serverId = serverId;
          local.status = 'synced';
          await local.save();
        }
      }
    } catch (e) {
      debugPrint('Error fetchProductores: $e');
    } finally {
      await loadLocalProductores();
    }
  }

  Future<void> manualRefresh() async {
    setState(() => loading = true);
    if (_isOnline) {
      await SyncService.syncAllPendingData();
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
                                    ),
                                    label: Text(
                                      isEditing ? 'Guardar' : 'Agregar',
                                      style: GoogleFonts.montserrat(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed:
                                        _submitProductor, // ¡AQUÍ SE USA LA NUEVA FUNCIÓN!
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
                                        borderRadius: BorderRadius.circular(8),
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
                          ...filteredProductores.map((productor) {
                            return FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _animationController,
                                curve: Curves.easeIn,
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
                                      if (productor.email?.isNotEmpty ?? false)
                                        Text(productor.email!),
                                      if (productor.cui?.isNotEmpty ?? false)
                                        Text('CUI: ${productor.cui!}'),
                                      if (productor.status == 'pending')
                                        Row(
                                          children: [
                                            const Icon(
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
                                              productorUuid: productor.uuid,
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
                                          children: const [
                                            Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Eliminar',
                                              style: TextStyle(
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
