import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../providers/balance_provider.dart';

class RoutineBuilderSheet extends StatefulWidget {
  const RoutineBuilderSheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const RoutineBuilderSheet(),
    );
  }

  @override
  State<RoutineBuilderSheet> createState() => _RoutineBuilderSheetState();
}

class _RoutineBuilderSheetState extends State<RoutineBuilderSheet> {
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  final List<Map<String, dynamic>> _exercises = [];

  Future<void> _addExercise() async {
    final durationStrRaw = _durationController.text.trim();
    final name = _nameController.text.trim();
    
    setState(() => _errorMessage = null);

    if (durationStrRaw.isEmpty || name.isEmpty) {
      setState(() => _errorMessage = 'Ingresa minutos y ejercicio');
      return;
    }
    
    final cleanDurationStr = durationStrRaw.replaceAll(RegExp(r'[^0-9.]'), '');
    final duration = double.tryParse(cleanDurationStr);
    
    if (duration == null || duration <= 0) {
      setState(() => _errorMessage = 'La duración no es válida');
      return;
    }

    final text = '${cleanDurationStr} min de $name';

    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token == null) return;
      
      final apiService = ApiService();
      // Temporalmente usamos el parse de alimentos adaptado o un endpoint nuevo
      // Por ahora creamos la UI, luego el endpoint /asistente/calcular-ejercicio
      final result = await apiService.calcularEjercicioManual(text, auth.token!);
      
      if (result['ejercicio'] != null) {
        setState(() {
          final ex = result['ejercicio'];
          _exercises.add({
            'name': ex['nombre'],
            'duration': '${ex['duracion']} min',
            'kcal': ex['calorias'],
            'met': ex['met'],
          });
        });
        _durationController.clear();
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
    _durationController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  double get totalKcal => _exercises.fold(0.0, (sum, item) => sum + (item['kcal'] as num).toDouble());
  double get totalMinutes => _exercises.fold(0.0, (sum, item) {
    final minStr = item['duration'].toString().replaceAll(' min', '');
    return sum + (double.tryParse(minStr) ?? 0.0);
  });

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
                  _buildExerciseList(),
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
            "Constructor de Rutinas",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Añade ejercicios y arma tu entrenamiento",
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
                  controller: _durationController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '15',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    border: InputBorder.none,
                    suffixText: 'min',
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
                      hintText: 'Press banca...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.fitness_center_rounded, color: Colors.grey.shade400, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isLoading ? null : _addExercise,
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: _isLoading ? Colors.grey : const Color(0xFF10B981), // Verde estilo fitness
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isLoading ? [] : [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.3),
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

  Widget _buildExerciseList() {
    if (_exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(Icons.directions_run_rounded, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("Tu rutina está vacía", style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _exercises.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _exercises[index];
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
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.fitness_center_rounded, color: Colors.green.shade400, size: 20),
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
                      item['duration'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _macroBadge("MET: ${item['met']}", Colors.blue.shade400),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${item['kcal'].toStringAsFixed(1)} kcal",
                    style: TextStyle(fontWeight: FontWeight.w800, color: Colors.orange.shade700, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _exercises.removeAt(index);
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
                  "Total Estimado",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      totalKcal.toStringAsFixed(1),
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
                _totalMacroColumn("Ejercicios", "${_exercises.length}", Colors.purple.shade400),
                _totalMacroColumn("Duración", "${totalMinutes.toStringAsFixed(0)} min", Colors.blue.shade400),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _exercises.isEmpty ? null : _saveRoutine,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text(
                  "Registrar Rutina",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveRoutine() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token == null) return;
      
      final apiService = ApiService();
      final result = await apiService.registrarRutinaManual(_exercises, auth.token!);
      
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rutina registrada con éxito'), backgroundColor: Colors.green),
          );
          setState(() { _exercises.clear(); });
          if (mounted) {
            await Provider.of<BalanceProvider>(context, listen: false)
                .fetchFullBalance(auth.token!);
            Navigator.pop(context);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['mensaje'] ?? 'Error al registrar')),
          );
        }
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
