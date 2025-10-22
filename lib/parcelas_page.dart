import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'visita_parcela.dart';

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
  List<dynamic> parcelas = [];
  List<dynamic> filteredParcelas = [];
  bool loading = false;

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _idParcelaController =
      TextEditingController(); // mostrado sólo en edición
  final _nombreController = TextEditingController();
  final _areaController = TextEditingController();
  final _tipoCultivoController = TextEditingController(); // display name
  final _idTipoCultivoController =
      TextEditingController(); // optional manual entry fallback
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  final _altitudController = TextEditingController();
  final _idMunicipioController = TextEditingController(); // optional fallback
  final _searchController = TextEditingController();
  bool _vigente = true;
  DateTime? _fechaRegistro;

  // Catalog selections
  int? _selectedTipoCultivoId; // selected id from catalog
  int? _selectedMunicipioId; // selected municipality id

  late AnimationController _animationController;

  bool isEditing = false;
  int? editingParcelaId;
  bool showForm = false;

  // IDs de parcelas que deben mostrar el indicador visual temporalmente
  final Set<int> _recentlyVisitedIds = {};
  final Duration _highlightDuration = const Duration(seconds: 4);

  // pagination config for pickers
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    fetchParcelas();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _searchController.addListener(() {
      filterParcelas(_searchController.text);
    });
  }

  @override
  void dispose() {
    _animation_controller_maybe_fix(); // no-op placeholder removed before using; keep analyzer clean
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
    super.dispose();
  }

  // Helper to avoid analyzer placeholder references (no-op).
  void _animation_controller_maybe_fix() {}

  Future<void> fetchParcelas() async {
    setState(() => loading = true);
    final supabase = Supabase.instance.client;
    final result = await supabase
        .from('parcelas')
        .select()
        .eq('id_productor', widget.productorId);
    setState(() {
      parcelas = result ?? [];
      filteredParcelas = parcelas;
      loading = false;
      _animationController.forward(from: 0);
    });
  }

  void filterParcelas(String query) {
    setState(() {
      final search = query.toLowerCase();
      filteredParcelas = parcelas.where((p) {
        final nombre = (p['nombre'] ?? '').toString().toLowerCase();
        final tipoCultivo = (p['tipo_cultivo'] ?? '').toString().toLowerCase();
        final area = (p['area'] ?? '').toString().toLowerCase();
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
    editingParcelaId = null;
    _selectedTipoCultivoId = null;
    _selectedMunicipioId = null;
    setState(() {
      showForm = false;
    });
  }

  Future<void> addParcela() async {
    if (!_formKey.currentState!.validate()) return;

    final supabase = Supabase.instance.client;

    // parse numeric values (use double for numeric)
    final double? area = double.tryParse(
      _areaController.text.replaceAll(',', '.'),
    );
    final double? lat = double.tryParse(
      _latitudController.text.replaceAll(',', '.'),
    );
    final double? lng = double.tryParse(
      _longitudController.text.replaceAll(',', '.'),
    );
    final double? alt = double.tryParse(
      _altitudController.text.replaceAll(',', '.'),
    );
    final int? idTipoCultivoFromField = int.tryParse(
      _idTipoCultivoController.text,
    );
    final int? idMunicipioFromField = int.tryParse(_idMunicipioController.text);

    // Prefer the selected catalog id, fallback to manual field
    final int? idTipoCultivoToSend =
        _selectedTipoCultivoId ?? idTipoCultivoFromField;
    final int? idMunicipioToSend = _selectedMunicipioId ?? idMunicipioFromField;

    // Use display name if provided
    final String tipoCultivoName = _tipoCultivoController.text;

    final nowIso = DateTime.now().toUtc().toIso8601String();

    await supabase.from('parcelas').insert({
      'nombre': _nombreController.text,
      'latitud': lat,
      'longitud': lng,
      'altitud': alt,
      'area': area,
      'tipo_cultivo': tipoCultivoName,
      'id_tipo_cultivo': idTipoCultivoToSend,
      'id_municipio': idMunicipioToSend,
      'id_productor': widget.productorId,
      'fecha_registro': nowIso,
      'vigente': _vigente,
    });

    clearFormFields();
    await fetchParcelas();
  }

  // NOTE: capture editingParcelaId into a local non-null variable before use
  Future<void> updateParcela() async {
    if (!isEditing || editingParcelaId == null) return;
    if (!_formKey.currentState!.validate()) return;

    final int id = editingParcelaId!;

    final supabase = Supabase.instance.client;

    final double? area = double.tryParse(
      _areaController.text.replaceAll(',', '.'),
    );
    final double? lat = double.tryParse(
      _latitudController.text.replaceAll(',', '.'),
    );
    final double? lng = double.tryParse(
      _longitudController.text.replaceAll(',', '.'),
    );
    final double? alt = double.tryParse(
      _altitudController.text.replaceAll(',', '.'),
    );
    final int? idTipoCultivoFromField = int.tryParse(
      _idTipoCultivoController.text,
    );
    final int? idMunicipioFromField = int.tryParse(_idMunicipioController.text);

    final int? idTipoCultivoToSend =
        _selectedTipoCultivoId ?? idTipoCultivoFromField;
    final int? idMunicipioToSend = _selectedMunicipioId ?? idMunicipioFromField;

    final String tipoCultivoName = _tipoCultivoController.text;

    await supabase
        .from('parcelas')
        .update({
          'nombre': _nombreController.text,
          'latitud': lat,
          'longitud': lng,
          'altitud': alt,
          'area': area,
          'tipo_cultivo': tipoCultivoName,
          'id_tipo_cultivo': idTipoCultivoToSend,
          'id_municipio': idMunicipioToSend,
          'vigente': _vigente,
        })
        .eq('id_parcela', id);

    clearFormFields();
    await fetchParcelas();
  }

  Future<void> deleteParcela(int id) async {
    final supabase = Supabase.instance.client;
    await supabase.from('parcelas').delete().eq('id_parcela', id);
    await fetchParcelas();
  }

  void startEditParcela(Map parcela) {
    setState(() {
      isEditing = true;
      // safe extraction to int?
      editingParcelaId = (parcela['id_parcela'] is int)
          ? parcela['id_parcela'] as int
          : int.tryParse(parcela['id_parcela']?.toString() ?? '');
      _idParcelaController.text = parcela['id_parcela']?.toString() ?? '';
      _nombreController.text = parcela['nombre'] ?? '';
      _areaController.text = parcela['area']?.toString() ?? '';
      // id_tipo_cultivo if present
      final parsedTipoId = (parcela['id_tipo_cultivo'] is int)
          ? parcela['id_tipo_cultivo'] as int
          : int.tryParse(parcela['id_tipo_cultivo']?.toString() ?? '');
      _selectedTipoCultivoId = parsedTipoId;
      _tipoCultivoController.text =
          parcela['tipo_cultivo'] ?? parcela['cultivo'] ?? '';
      _idTipoCultivoController.text =
          parcela['id_tipo_cultivo']?.toString() ?? '';
      _latitudController.text = parcela['latitud']?.toString() ?? '';
      _longitudController.text = parcela['longitud']?.toString() ?? '';
      _altitudController.text = parcela['altitud']?.toString() ?? '';
      final parsedMunicipio = (parcela['id_municipio'] is int)
          ? parcela['id_municipio'] as int
          : int.tryParse(parcela['id_municipio']?.toString() ?? '');
      _selectedMunicipioId = parsedMunicipio;
      _idMunicipioController.text = parsedMunicipio?.toString() ?? '';
      _vigente = parcela['vigente'] == null
          ? true
          : (parcela['vigente'] as bool? ?? true);
      // fecha_registro viene como timestamptz; sólo para mostrar
      try {
        _fechaRegistro = parcela['fecha_registro'] != null
            ? DateTime.parse(parcela['fecha_registro'].toString()).toLocal()
            : null;
      } catch (_) {
        _fechaRegistro = null;
      }

      showForm = true;
    });
  }

  void startAddParcela() {
    clearFormFields();
    setState(() {
      showForm = true;
    });
  }

  // Resalta una parcela por su id durante _highlightDuration
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

  Future<void> _pickFechaRegistro(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaRegistro ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fechaRegistro = picked;
      });
    }
  }

  // ------ PICKER GENERIC FOR PAGINATED CATALOGS (tipo_cultivo / municipios) ------
  Future<Map<String, dynamic>?> _openCatalogPicker({
    required String table,
    required String idColumn,
    required String labelColumn,
    String? initialSearch,
    Map<String, String>? extraFilters,
  }) async {
    // returns selected row as Map or null
    final supabase = Supabase.instance.client;
    final ScrollController scrollController = ScrollController();
    List<Map<String, dynamic>> items = [];
    bool loadingMore = false;
    bool hasMore = true;
    int offset = 0;
    String searchTerm = initialSearch ?? '';

    // Reemplaza solo la función loadPage dentro de la implementación de _openCatalogPicker
    Future<void> loadPage() async {
      if (!hasMore || loadingMore) return;
      loadingMore = true;
      try {
        final supabase = Supabase.instance.client;

        // Construimos la consulta paso a paso en una variable dinámica.
        dynamic query = supabase.from(table).select('$idColumn, $labelColumn');

        // Aplicar búsqueda (ilike) SIEMPRE antes de order/range
        if (searchTerm.isNotEmpty) {
          // ilike está disponible en el builder resultante; usando 'dynamic' evitamos el error de tipado
          query = query.ilike(labelColumn, '%$searchTerm%');
        }

        // Aplicar filtros adicionales (si los hay) antes de ordenar
        if (extraFilters != null) {
          extraFilters.forEach((k, v) {
            query = query.eq(k, v);
          });
        }

        // Finalmente ordenar y solicitar el rango (paginación)
        final res = await query
            .order(labelColumn, ascending: true)
            .range(offset, offset + _pageSize - 1);

        final List<dynamic> page = res ?? [];
        final mapped = page.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e as Map);
          return <String, dynamic>{};
        }).toList();

        if (mapped.length < _pageSize) hasMore = false;
        offset += mapped.length;
        items.addAll(mapped);
      } catch (e) {
        debugPrint('Error loading $table page: $e');
        hasMore = false;
      } finally {
        loadingMore = false;
      }
    }

    // show modal bottom sheet with search + list
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        // load first page immediately
        loadPage();
        return StatefulBuilder(
          builder: (context, setModalState) {
            scrollController.addListener(() {
              if (scrollController.position.pixels >=
                  scrollController.position.maxScrollExtent - 120) {
                // near bottom
                if (!loadingMore && hasMore) {
                  loadPage().then((_) => setModalState(() {}));
                }
              }
            });

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Buscar...',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (v) async {
                                searchTerm = v;
                                // reset pagination
                                offset = 0;
                                items.clear();
                                hasMore = true;
                                await loadPage();
                                setModalState(() {});
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: items.isEmpty
                          ? Center(
                              child: hasMore
                                  ? const CircularProgressIndicator()
                                  : const Text('No hay resultados'),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: items.length + (hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= items.length) {
                                  // loading indicator row
                                  // trigger load in case
                                  if (!loadingMore && hasMore) {
                                    loadPage().then(
                                      (_) => setModalState(() {}),
                                    );
                                  }
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final itm = items[index];
                                final id = itm[idColumn];
                                final label =
                                    itm[labelColumn]?.toString() ??
                                    '(sin nombre)';
                                return ListTile(
                                  title: Text(label),
                                  subtitle: Text(id?.toString() ?? ''),
                                  onTap: () => Navigator.of(ctx).pop(itm),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // wrappers for tipo_cultivo and municipios
  Future<void> _pickTipoCultivo() async {
    final selected = await _openCatalogPicker(
      table: 'tipo_cultivo',
      idColumn: 'id',
      labelColumn: 'cultivo',
    );
    if (selected != null) {
      setState(() {
        _selectedTipoCultivoId = (selected['id'] is int)
            ? selected['id'] as int
            : int.tryParse(selected['id']?.toString() ?? '');
        _tipoCultivoController.text = (selected['cultivo'] ?? '').toString();
      });
    }
  }

  Future<void> _pickMunicipio() async {
    final selected = await _openCatalogPicker(
      table: 'municipios',
      idColumn: 'id_municipio',
      labelColumn: 'nombre',
    );
    if (selected != null) {
      setState(() {
        _selectedMunicipioId = (selected['id_municipio'] is int)
            ? selected['id_municipio'] as int
            : int.tryParse(selected['id_municipio']?.toString() ?? '');
        _idMunicipioController.text =
            (selected['nombre'] ?? selected['id_municipio']?.toString() ?? '')
                .toString();
      });
    }
  }

  Widget _buildNumberField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool allowDecimal = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return null; // allow empty
        final parsed = allowDecimal
            ? double.tryParse(v.replaceAll(',', '.'))
            : int.tryParse(v);
        if (parsed == null) return 'Valor inválido';
        return null;
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
      ),
      floatingActionButton: showForm
          ? null
          : FloatingActionButton(
              backgroundColor: natureGreen,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: startAddParcela,
              tooltip: 'Agregar Parcela',
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12.0),
              children: [
                // IMAGEN SUPERIOR
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

                // BUSCADOR
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

                // FORMULARIO (agregar / editar)
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
                        vertical: 12,
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
                            const SizedBox(height: 8),

                            // id_parcela (solo lectura en edición)
                            if (isEditing)
                              TextFormField(
                                controller: _idParcelaController,
                                decoration: const InputDecoration(
                                  labelText: 'ID Parcela',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(),
                                ),
                                readOnly: true,
                              ),

                            const SizedBox(height: 8),

                            // Nombre
                            TextFormField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon: Icon(
                                  Icons.landscape,
                                  color: Colors.green,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty)
                                  return 'Ingresa nombre';
                                return null;
                              },
                            ),

                            const SizedBox(height: 8),

                            // Area
                            _buildNumberField(
                              _areaController,
                              'Área (numeric)',
                              hint: 'ej. 1.5',
                            ),

                            const SizedBox(height: 8),

                            // Tipo de cultivo: opens paginated searchable picker
                            TextFormField(
                              readOnly: true,
                              controller: _tipoCultivoController,
                              decoration: InputDecoration(
                                labelText:
                                    'Tipo cultivo (seleccionar catálogo)',
                                prefixIcon: const Icon(Icons.grass),
                                filled: true,
                                fillColor: Colors.white,
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _pickTipoCultivo,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // id_tipo_cultivo manual (opcional)
                            TextFormField(
                              controller: _idTipoCultivoController,
                              decoration: const InputDecoration(
                                labelText: 'ID tipo cultivo (opcional)',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),

                            const SizedBox(height: 8),

                            // Lat / Lng / Alt
                            _buildNumberField(
                              _latitudController,
                              'Latitud',
                              hint: 'ej. 12.345678',
                            ),
                            const SizedBox(height: 8),
                            _buildNumberField(
                              _longitudController,
                              'Longitud',
                              hint: 'ej. -87.123456',
                            ),
                            const SizedBox(height: 8),
                            _buildNumberField(
                              _altitudController,
                              'Altitud',
                              hint: 'ej. 120.5',
                            ),

                            const SizedBox(height: 8),

                            // Municipio: opens paginated searchable picker
                            TextFormField(
                              readOnly: true,
                              controller: _idMunicipioController,
                              decoration: InputDecoration(
                                labelText: 'Municipio (seleccionar catálogo)',
                                prefixIcon: const Icon(Icons.location_city),
                                filled: true,
                                fillColor: Colors.white,
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _pickMunicipio,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // vigente & fecha registro row
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Text('Vigente:'),
                                      const SizedBox(width: 8),
                                      Switch(
                                        value: _vigente,
                                        onChanged: (val) {
                                          setState(() {
                                            _vigente = val;
                                          });
                                        },
                                        activeColor: natureGreen,
                                      ),
                                    ],
                                  ),
                                ),
                                // Fecha registro (editable si lo desea)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickFechaRegistro(context),
                                    icon: const Icon(Icons.calendar_today),
                                    label: Text(
                                      _fechaRegistro == null
                                          ? 'Fecha registro (auto)'
                                          : 'Fecha: ${DateFormat('dd/MM/yyyy').format(_fechaRegistro!)}',
                                      style: GoogleFonts.montserrat(),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: Icon(
                                      isEditing ? Icons.save : Icons.add,
                                      color: Colors.white,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isEditing
                                          ? Colors.orange
                                          : natureGreen,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
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
                                    onPressed: () async {
                                      if (isEditing) {
                                        await updateParcela();
                                      } else {
                                        await addParcela();
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
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
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

                // Lista de parcelas con animación and badge of new visit
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Column(
                      children: [
                        ...filteredParcelas.asMap().entries.map((entry) {
                          final i = entry.key;
                          final parcela = Map<String, dynamic>.from(
                            entry.value as Map,
                          );
                          final parcelaId = (parcela['id_parcela'] is int)
                              ? parcela['id_parcela'] as int
                              : int.tryParse(
                                      parcela['id_parcela']?.toString() ?? '',
                                    ) ??
                                    0;

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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: ListTile(
                                            onTap: () async {
                                              final parcelaIdString = parcelaId
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
                                              parcela['nombre'] ?? '',
                                              style: GoogleFonts.montserrat(
                                                color: natureGreen,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if ((parcela['tipo_cultivo'] ??
                                                        '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.grass,
                                                        size: 16,
                                                        color:
                                                            Colors.green[600],
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        parcela['tipo_cultivo']
                                                                ?.toString() ??
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
                                                if ((parcela['area'] ?? '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.square_foot,
                                                        size: 16,
                                                        color:
                                                            Colors.green[600],
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        parcela['area']
                                                                ?.toString() ??
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
                                              ],
                                            ),
                                            trailing: PopupMenuButton<String>(
                                              icon: Icon(
                                                Icons.more_vert,
                                                color: natureGreen,
                                              ),
                                              onSelected: (value) async {
                                                if (value == 'edit') {
                                                  startEditParcela(parcela);
                                                } else if (value == 'visita') {
                                                  final parcelaIdString =
                                                      parcelaId.toString();
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
                                                } else if (value == 'delete') {
                                                  final confirmed = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text(
                                                        'Confirmar eliminación',
                                                      ),
                                                      content: Text(
                                                        '¿Eliminar la parcela "${parcela['nombre']}"?',
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
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirmed == true) {
                                                    await deleteParcela(
                                                      parcelaId,
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
                                                      const SizedBox(width: 8),
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
                                                        Icons.medical_services,
                                                        color: natureGreen,
                                                      ),
                                                      const SizedBox(width: 8),
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
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Eliminar',
                                                        style:
                                                            GoogleFonts.montserrat(
                                                              color: Colors.red,
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
                                      // Badge para nueva visita
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: AnimatedOpacity(
                                          opacity: isHighlighted ? 1.0 : 0.0,
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
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
                                                  style: GoogleFonts.montserrat(
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
    );
  }
}
