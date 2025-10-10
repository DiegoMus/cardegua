import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class ParcelasPage extends StatefulWidget {
  final int productorId;
  final String? nombreProductor;
  const ParcelasPage({
    super.key,
    required this.productorId,
    this.nombreProductor,
  });

  @override
  State<ParcelasPage> createState() => _ParcelasPageState();
}

class _ParcelasPageState extends State<ParcelasPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> parcelas = [];
  List<dynamic> departamentos = [];
  List<dynamic> municipios = [];
  int? selectedDepartamentoId;
  int? selectedMunicipioId;

  bool loading = false;

  final _nombreController = TextEditingController();
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  final _altitudController = TextEditingController();
  final _tipoCultivoController = TextEditingController();
  final _hectareasController = TextEditingController();

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    fetchDepartamentos();
    fetchParcelas();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nombreController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    _altitudController.dispose();
    _tipoCultivoController.dispose();
    _hectareasController.dispose();
    super.dispose();
  }

  Future<void> fetchDepartamentos() async {
    final supabase = Supabase.instance.client;
    final result = await supabase.from('departamentos').select();
    setState(() {
      departamentos = result;
    });
  }

  Future<void> fetchMunicipios(int departamentoId) async {
    final supabase = Supabase.instance.client;
    final result = await supabase
        .from('municipios')
        .select()
        .eq('id_departamento', departamentoId);
    setState(() {
      municipios = result;
      selectedMunicipioId = null;
    });
  }

  Future<void> fetchParcelas() async {
    setState(() => loading = true);
    final supabase = Supabase.instance.client;
    final result = await supabase
        .from('parcelas')
        .select()
        .eq('id_productor', widget.productorId);
    setState(() {
      parcelas = result;
      loading = false;
      _animationController.forward(from: 0);
    });
  }

  Future<void> addParcela() async {
    if (selectedMunicipioId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un municipio')));
      return;
    }
    final supabase = Supabase.instance.client;
    await supabase.from('parcelas').insert({
      'nombre': _nombreController.text,
      'area': double.tryParse(_hectareasController.text) ?? 0,
      'latitud': _latitudController.text,
      'longitud': _longitudController.text,
      'altitud': _altitudController.text,
      'tipo_cultivo': _tipoCultivoController.text,
      'id_productor': widget.productorId,
      'id_municipio': selectedMunicipioId,
    });
    _nombreController.clear();
    _hectareasController.clear();
    _latitudController.clear();
    _longitudController.clear();
    _altitudController.clear();
    _tipoCultivoController.clear();
    selectedDepartamentoId = null;
    municipios = [];
    selectedMunicipioId = null;
    fetchParcelas();
  }

  Future<void> updateParcela(
    int id,
    String nombre,
    double area,
    String latitud,
    String longitud,
    String altitud,
    String tipoCultivo,
    int municipioId,
  ) async {
    final supabase = Supabase.instance.client;
    await supabase
        .from('parcelas')
        .update({
          'nombre': nombre,
          'area': area,
          'latitud': latitud,
          'longitud': longitud,
          'altitud': altitud,
          'tipo_cultivo': tipoCultivo,
          'id_municipio': municipioId,
        })
        .eq('id_parcela', id);
    fetchParcelas();
  }

  Future<void> deleteParcela(int id) async {
    final supabase = Supabase.instance.client;
    await supabase.from('parcelas').delete().eq('id_parcela', id);
    fetchParcelas();
  }

  void showEditDialog(Map parcela) {
    _nombreController.text = parcela['nombre'] ?? '';
    _hectareasController.text = parcela['area']?.toString() ?? '';
    _latitudController.text = parcela['latitud'] ?? '';
    _longitudController.text = parcela['longitud'] ?? '';
    _altitudController.text = parcela['altitud'] ?? '';
    _tipoCultivoController.text = parcela['tipo_cultivo'] ?? '';
    selectedDepartamentoId = null;
    municipios = [];
    selectedMunicipioId = parcela['id_municipio'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFeafbe7),
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              'Editar Parcela',
              style: GoogleFonts.montserrat(color: Colors.green[800]),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(
                    Icons.landscape,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
              ),
              TextField(
                controller: _hectareasController,
                decoration: const InputDecoration(
                  labelText: 'Hectáreas',
                  prefixIcon: Icon(
                    Icons.square_foot,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
              ),
              TextField(
                controller: _latitudController,
                decoration: const InputDecoration(
                  labelText: 'Latitud',
                  prefixIcon: Icon(Icons.place, color: Colors.green, size: 20),
                ),
              ),
              TextField(
                controller: _longitudController,
                decoration: const InputDecoration(
                  labelText: 'Longitud',
                  prefixIcon: Icon(
                    Icons.place_outlined,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
              ),
              TextField(
                controller: _altitudController,
                decoration: const InputDecoration(
                  labelText: 'Altitud',
                  prefixIcon: Icon(Icons.height, color: Colors.green, size: 20),
                ),
              ),
              TextField(
                controller: _tipoCultivoController,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Cultivo',
                  prefixIcon: Icon(Icons.eco, color: Colors.green, size: 20),
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: selectedDepartamentoId,
                decoration: const InputDecoration(
                  labelText: 'Departamento',
                  prefixIcon: Icon(Icons.map, color: Colors.green, size: 20),
                  border: OutlineInputBorder(),
                ),
                items: departamentos.map<DropdownMenuItem<int>>((dpto) {
                  return DropdownMenuItem<int>(
                    value: dpto['id_departamento'],
                    child: Text(dpto['nombre']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedDepartamentoId = value;
                    municipios = [];
                    selectedMunicipioId = null;
                  });
                  if (value != null) {
                    fetchMunicipios(value);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: selectedMunicipioId,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  prefixIcon: Icon(
                    Icons.location_city,
                    color: Colors.green,
                    size: 20,
                  ),
                  border: OutlineInputBorder(),
                ),
                items: municipios.map<DropdownMenuItem<int>>((mun) {
                  return DropdownMenuItem<int>(
                    value: mun['id_municipio'],
                    child: Text(mun['nombre']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedMunicipioId = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              updateParcela(
                parcela['id_parcela'],
                _nombreController.text,
                double.tryParse(_hectareasController.text) ?? 0,
                _latitudController.text,
                _longitudController.text,
                _altitudController.text,
                _tipoCultivoController.text,
                selectedMunicipioId ?? parcela['id_municipio'],
              );
              Navigator.pop(context);
            },
            child: Row(
              children: [
                const Icon(Icons.save, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                Text(
                  'Guardar',
                  style: GoogleFonts.montserrat(color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
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
          widget.nombreProductor != null
              ? 'Parcelas de ${widget.nombreProductor}'
              : 'Parcelas',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12.0),
              children: [
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
                          'Nueva Parcela',
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
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _hectareasController,
                          decoration: const InputDecoration(
                            labelText: 'Area (Ha)',
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
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _latitudController,
                          decoration: const InputDecoration(
                            labelText: 'Latitud',
                            prefixIcon: Icon(
                              Icons.place,
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
                          controller: _longitudController,
                          decoration: const InputDecoration(
                            labelText: 'Longitud',
                            prefixIcon: Icon(
                              Icons.place_outlined,
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
                          controller: _altitudController,
                          decoration: const InputDecoration(
                            labelText: 'Altitud',
                            prefixIcon: Icon(
                              Icons.height,
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
                          controller: _tipoCultivoController,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Cultivo',
                            prefixIcon: Icon(
                              Icons.eco,
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
                        DropdownButtonFormField<int>(
                          initialValue: selectedDepartamentoId,
                          decoration: const InputDecoration(
                            labelText: 'Departamento',
                            prefixIcon: Icon(
                              Icons.map,
                              color: Colors.green,
                              size: 20,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: departamentos.map<DropdownMenuItem<int>>((
                            dpto,
                          ) {
                            return DropdownMenuItem<int>(
                              value: dpto['id_departamento'],
                              child: Text(dpto['nombre']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedDepartamentoId = value;
                              municipios = [];
                              selectedMunicipioId = null;
                            });
                            if (value != null) {
                              fetchMunicipios(value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: selectedMunicipioId,
                          decoration: const InputDecoration(
                            labelText: 'Municipio',
                            prefixIcon: Icon(
                              Icons.location_city,
                              color: Colors.green,
                              size: 20,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: municipios.map<DropdownMenuItem<int>>((mun) {
                            return DropdownMenuItem<int>(
                              value: mun['id_municipio'],
                              child: Text(mun['nombre']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedMunicipioId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: natureGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 18,
                            ),
                          ),
                          label: Text(
                            'Agregar Parcela',
                            style: GoogleFonts.montserrat(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: addParcela,
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
                        ...parcelas.asMap().entries.map((entry) {
                          final i = entry.key;
                          final parcela = entry.value;
                          return FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _animationController,
                              curve: Interval(
                                i / (parcelas.isEmpty ? 1 : parcelas.length),
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
                                subtitle: Row(
                                  children: [
                                    Icon(
                                      Icons.square_foot,
                                      size: 16,
                                      color: Colors.green[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ha: ${parcela['area'] ?? 'N/A'}',
                                      style: GoogleFonts.montserrat(
                                        color: Colors.green[800],
                                        fontSize: 13,
                                      ),
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
                                      showEditDialog(parcela);
                                    } else if (value == 'delete') {
                                      deleteParcela(parcela['id_parcela']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, color: natureGreen),
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
                                          Icon(Icons.delete, color: Colors.red),
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
    );
  }
}
