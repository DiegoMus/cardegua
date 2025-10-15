import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'parcelas_page.dart';
import 'package:google_fonts/google_fonts.dart';

class ProductoresPage extends StatefulWidget {
  const ProductoresPage({super.key});

  @override
  State<ProductoresPage> createState() => _ProductoresPageState();
}

class _ProductoresPageState extends State<ProductoresPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> productores = [];
  List<dynamic> filteredProductores = [];
  bool loading = false;

  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _cuiController = TextEditingController();
  final _searchController = TextEditingController();

  late AnimationController _animationController;

  bool isEditing = false;
  int? editingProductorId;
  bool showForm = false; // controla si el formulario está visible

  @override
  void initState() {
    super.initState();
    fetchProductores();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _searchController.addListener(() {
      filterProductores(_searchController.text);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _cuiController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchProductores() async {
    setState(() => loading = true);
    final supabase = Supabase.instance.client;
    final result = await supabase.from('productores').select();
    setState(() {
      productores = result;
      filteredProductores = result;
      loading = false;
      _animationController.forward(from: 0);
    });
  }

  void filterProductores(String query) {
    setState(() {
      final search = query.toLowerCase();
      filteredProductores = productores.where((p) {
        final nombre = (p['nombre'] ?? '').toLowerCase();
        final cui = (p['cui'] ?? '').toLowerCase();
        return nombre.contains(search) || cui.contains(search);
      }).toList();
    });
  }

  void clearFormFields() {
    _nombreController.clear();
    _emailController.clear();
    _telephoneController.clear();
    _cuiController.clear();
    isEditing = false;
    editingProductorId = null;
    setState(() {
      showForm = false;
    });
  }

  Future<void> addProductor() async {
    final supabase = Supabase.instance.client;
    await supabase.from('productores').insert({
      'nombre': _nombreController.text,
      'email': _emailController.text,
      'telefono': _telephoneController.text,
      'cui': _cuiController.text,
    });
    clearFormFields();
    fetchProductores();
  }

  Future<void> updateProductor(
    int id,
    String nombre,
    String email,
    String telefono,
    String cui,
  ) async {
    final supabase = Supabase.instance.client;
    await supabase
        .from('productores')
        .update({
          'nombre': nombre,
          'email': email,
          'telefono': telefono,
          'cui': cui,
        })
        .eq('id_productor', id);
    clearFormFields();
    fetchProductores();
  }

  Future<void> deleteProductor(int id) async {
    final supabase = Supabase.instance.client;
    await supabase.from('productores').delete().eq('id_productor', id);
    fetchProductores();
  }

  void startEditProductor(Map productor) {
    setState(() {
      isEditing = true;
      editingProductorId = productor['id_productor'];
      _nombreController.text = productor['nombre'] ?? '';
      _emailController.text = productor['email'] ?? '';
      _telephoneController.text = productor['telefono'] ?? '';
      _cuiController.text = productor['cui'] ?? '';
      showForm = true;
    });
  }

  void startAddProductor() {
    clearFormFields();
    setState(() {
      showForm = true;
    });
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
          : ListView(
              padding: const EdgeInsets.all(12.0),
              children: [
                // IMAGEN SUPERIOR
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/productores_header.png', // Cambia según tu asset
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                // BUSCADOR
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
                            isEditing ? 'Editar Productor' : 'Nuevo Productor',
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
                                        editingProductorId != null) {
                                      updateProductor(
                                        editingProductorId!,
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
                                  child: Icon(Icons.person, color: natureGreen),
                                ),
                                title: Text(
                                  productor['nombre'] ?? '',
                                  style: GoogleFonts.montserrat(
                                    color: natureGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          productor['email'] ?? '',
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
                                          productor['cui'] ?? '',
                                          style: GoogleFonts.montserrat(
                                            color: Colors.green[800],
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
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      startEditProductor(productor);
                                    } else if (value == 'delete') {
                                      deleteProductor(
                                        productor['id_productor'],
                                      );
                                    } else if (value == 'parcelas') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ParcelasPage(
                                            productorId:
                                                productor['id_productor'],
                                            nombreProductor:
                                                productor['nombre'] ?? '',
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
                        if (filteredProductores.isEmpty)
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
    );
  }
}
