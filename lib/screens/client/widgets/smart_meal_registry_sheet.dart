import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../providers/balance_provider.dart';

class SmartMealRegistrySheet extends StatefulWidget {
  const SmartMealRegistrySheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SmartMealRegistrySheet(),
    );
  }

  @override
  State<SmartMealRegistrySheet> createState() => _SmartMealRegistrySheetState();
}

class _SmartMealRegistrySheetState extends State<SmartMealRegistrySheet> {
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  final List<Map<String, dynamic>> _ingredients = [];

  Future<void> _addIngredient() async {
    final qtyStrRaw = _qtyController.text.trim();
    final name = _nameController.text.trim();
    
    setState(() => _errorMessage = null);

    if (qtyStrRaw.isEmpty || name.isEmpty) {
      setState(() => _errorMessage = 'Ingresa cantidad y alimento');
      return;
    }
    
    // Limpiar caracteres no numéricos por si acaso (ej. si ponen "200g" en vez de "200")
    final cleanQtyStr = qtyStrRaw.replaceAll(RegExp(r'[^0-9.]'), '');
    final qty = double.tryParse(cleanQtyStr);
    
    if (qty == null || qty <= 0) {
      setState(() => _errorMessage = 'La cantidad no es válida');
      return;
    }

    final text = '${cleanQtyStr}g de $name';

    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token == null) return;
      
      final apiService = ApiService();
      final result = await apiService.parseIngredients(text, auth.token!);
      
      if (result['ingredientes'] != null) {
        setState(() {
          for (var item in result['ingredientes']) {
            _ingredients.add({
              'name': item['nombre'],
              'quantity': '${item['gramos_totales']}g (${item['cantidad']} ${item['unidad']})',
              'grams': item['gramos_totales'],
              'kcal': item['calorias'],
              'p': item['proteinas_g'],
              'c': item['carbohidratos_g'],
              'g': item['grasas_g'],
            });
          }
        });
        _qtyController.clear();
        _nameController.clear();
      } else {
        setState(() => _errorMessage = 'No se encontró información.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  double get totalKcal => _ingredients.fold(0.0, (sum, item) => sum + (item['kcal'] as num).toDouble());
  double get totalP => _ingredients.fold(0.0, (sum, item) => sum + (item['p'] as num).toDouble());
  double get totalC => _ingredients.fold(0.0, (sum, item) => sum + (item['c'] as num).toDouble());
  double get totalG => _ingredients.fold(0.0, (sum, item) => sum + (item['g'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: kToolbarHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: _KeyboardPadding(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  _buildInputSection(),
                  const Divider(height: 1, color: Color(0xFFF0F2F5)),
                  _buildIngredientList(),
                  _buildStickyFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Registro Inteligente",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Añade alimentos o recetas en lenguaje natural",
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 90,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '200',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    border: InputBorder.none,
                    suffixText: 'g',
                    suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'arroz...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.restaurant_menu_rounded, color: Colors.grey.shade400, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isLoading ? null : _addIngredient,
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: _isLoading ? Colors.grey : const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isLoading ? [] : [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: _isLoading 
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIngredientList() {
    if (_ingredients.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(Icons.shopping_basket_outlined, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("Tu plato está vacío", style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _ingredients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _ingredients[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_food_beverage_rounded, color: Colors.orange.shade400, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['quantity'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _macroBadge("P: ${item['p']}g", Colors.red.shade400),
                        const SizedBox(width: 6),
                        _macroBadge("C: ${item['c']}g", Colors.orange.shade400),
                        const SizedBox(width: 6),
                        _macroBadge("G: ${item['g']}g", Colors.blue.shade400),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${item['kcal']} kcal",
                    style: TextStyle(fontWeight: FontWeight.w800, color: Colors.orange.shade700, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _ingredients.removeAt(index);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.close_rounded, size: 16, color: Colors.red.shade300),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _macroBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStickyFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total Acumulado",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      totalKcal.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3, left: 2),
                      child: Text(" kcal", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _totalMacroColumn("Proteínas", "${totalP.toStringAsFixed(1)}g", Colors.red.shade400),
                _totalMacroColumn("Carbohidratos", "${totalC.toStringAsFixed(1)}g", Colors.orange.shade400),
                _totalMacroColumn("Grasas", "${totalG.toStringAsFixed(1)}g", Colors.blue.shade400),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _ingredients.isEmpty ? null : _saveRegistro,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text(
                  "Guardar Registro",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRegistro() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token == null) return;
      final apiService = ApiService();
      for (final ing in List.from(_ingredients)) {
        await apiService.registrarManualAlimento(
          nombre: ing['name'] as String,
          calorias: (ing['kcal'] as num).toDouble(),
          proteinasG: (ing['p'] as num).toDouble(),
          carbohidratosG: (ing['c'] as num).toDouble(),
          grasasG: (ing['g'] as num).toDouble(),
          porcionG: (ing['grams'] as num? ?? 100).toDouble(),
          token: auth.token!,
        );
      }
      if (mounted) {
        await Provider.of<BalanceProvider>(context, listen: false)
            .fetchFullBalance(auth.token!);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro guardado con éxito'),
            backgroundColor: Colors.green,
          ),
        );
        _ingredients.clear();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _totalMacroColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _KeyboardPadding extends StatelessWidget {
  final Widget child;
  
  const _KeyboardPadding({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    );
  }
}
