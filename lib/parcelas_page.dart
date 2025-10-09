import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ParcelasPage extends StatefulWidget {
  final int productorId;
  const ParcelasPage({super.key, required this.productorId});

  @override
  State<ParcelasPage> createState() => _ParcelasPageState();
}

class _ParcelasPageState extends State<ParcelasPage> {
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

  @override
  void initState() {
    super.initState();
    fetchDepartamentos();
    fetchParcelas();
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
      'hectareas': double.tryParse(_hectareasController.text) ?? 0,
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
    double hectareas,
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
          'hectareas': hectareas,
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
    _hectareasController.text = parcela['hectareas']?.toString() ?? '';
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
        title: const Text('Editar Parcela'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: _hectareasController,
                decoration: const InputDecoration(labelText: 'Hectáreas'),
              ),
              TextField(
                controller: _latitudController,
                decoration: const InputDecoration(labelText: 'Latitud'),
              ),
              TextField(
                controller: _longitudController,
                decoration: const InputDecoration(labelText: 'Longitud'),
              ),
              TextField(
                controller: _altitudController,
                decoration: const InputDecoration(labelText: 'Altitud'),
              ),
              TextField(
                controller: _tipoCultivoController,
                decoration: const InputDecoration(labelText: 'Tipo de Cultivo'),
              ),
              DropdownButton<int>(
                value: selectedDepartamentoId,
                hint: const Text('Seleccione departamento'),
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
              DropdownButton<int>(
                value: selectedMunicipioId,
                hint: const Text('Seleccione municipio'),
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
                parcela['id'],
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
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcelas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nombreController,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                      ),
                      TextField(
                        controller: _hectareasController,
                        decoration: const InputDecoration(
                          labelText: 'Hectáreas',
                        ),
                      ),
                      TextField(
                        controller: _latitudController,
                        decoration: const InputDecoration(labelText: 'Latitud'),
                      ),
                      TextField(
                        controller: _longitudController,
                        decoration: const InputDecoration(
                          labelText: 'Longitud',
                        ),
                      ),
                      TextField(
                        controller: _altitudController,
                        decoration: const InputDecoration(labelText: 'Altitud'),
                      ),
                      TextField(
                        controller: _tipoCultivoController,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de Cultivo',
                        ),
                      ),
                      DropdownButton<int>(
                        value: selectedDepartamentoId,
                        hint: const Text('Seleccione departamento'),
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
                      DropdownButton<int>(
                        value: selectedMunicipioId,
                        hint: const Text('Seleccione municipio'),
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
                      ElevatedButton(
                        onPressed: addParcela,
                        child: const Text('Agregar Parcela'),
                      ),
                    ],
                  ),
                ),
                ...parcelas.map(
                  (parcela) => ListTile(
                    title: Text(parcela['nombre'] ?? ''),
                    subtitle: Text('Hectáreas: ${parcela['hectareas']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => showEditDialog(parcela),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => deleteParcela(parcela['id_parcela']),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
