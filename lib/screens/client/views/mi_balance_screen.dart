import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service.dart';
import '../../../providers/auth_provider.dart';
import 'chat_screen.dart';
import '../../../models/suggestion.dart';
import '../../../providers/balance_provider.dart';
import 'edit_profile_screen.dart';
import '../widgets/routine_builder_sheet.dart';
import '../widgets/smart_meal_registry_sheet.dart';

class MiBalanceScreen extends StatefulWidget {
  const MiBalanceScreen({Key? key}) : super(key: key);

  @override
  State<MiBalanceScreen> createState() => _MiBalanceScreenState();
}

class _MiBalanceScreenState extends State<MiBalanceScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  late AnimationController _animController;

  bool isLocalLoading = false;
  String? errorMessage;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final balance = Provider.of<BalanceProvider>(context, listen: false);
    if (auth.token != null) {
      String? dateParam;
      if (_selectedDate != null) {
        dateParam = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
      }
      balance.fetchFullBalance(auth.token!, fecha: dateParam).then((_) {
        // Asegúrate que el controller no haga forward si el widget muere
        if (mounted) _animController.forward(from: 0);
      });
      balance.fetchSuggestions(auth.token!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    setState(() {
      isLocalLoading = true;
      errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      if (token == null) throw Exception('No hay sesión activa');

      String? dateParam;
      if (_selectedDate != null) {
        dateParam = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
      }

      await Provider.of<BalanceProvider>(context, listen: false).fetchFullBalance(token, fecha: dateParam);
      _animController.forward(from: 0);
      if (mounted) setState(() => isLocalLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLocalLoading = false;
        });
      }
    }
  }

  Future<void> _eliminarRegistro(int id, String tipo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 10),
            const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('¿Eliminar este ${tipo == 'alimento' ? 'alimento' : 'ejercicio'} de tu registro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      await _apiService.eliminarRegistro(id, tipo, token!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${tipo == 'alimento' ? 'Alimento' : 'Ejercicio'} eliminado'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      
      String? dateParam;
      if (_selectedDate != null) {
        dateParam = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
      }
      await Provider.of<BalanceProvider>(context, listen: false).fetchFullBalance(token, fecha: dateParam);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BalanceProvider>(
      builder: (context, provider, child) {
        final balanceData = provider.fullBalanceData;
        final isLoading = isLocalLoading && balanceData == null;

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: isLoading
              ? _buildLoadingState()
              : errorMessage != null
                  ? _buildErrorView()
                  : balanceData == null
                      ? _buildEmptyDayState()
                      : _buildPremiumBalance(balanceData),
          bottomNavigationBar: _buildBottomNavigation(),
          floatingActionButton: _buildFABRegistro(),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(const Color(0xFF1E88E5)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Cargando tu balance...', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEmptyDayState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Text('Sin datos disponibles', style: TextStyle(color: Colors.grey.shade600, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Registra tu primera comida en el asistente', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadBalance,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Recargar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumBalance(Map<String, dynamic> data) {
    final resumen = data['resumen'] ?? {};
    final alimentos = data['alimentos_registrados'] ?? [];
    final ejercicios = data['ejercicios_registrados'] ?? [];

    final consumidas = (resumen['calorias_consumidas'] ?? 0).toDouble();
    final quemadas = (resumen['calorias_quemadas'] ?? 0).toDouble();
    final objetivo = (resumen['objetivo_diario'] ?? 2000).toDouble();
    final restantes = (resumen['calorias_restantes'] ?? (objetivo - consumidas + quemadas)).toDouble();
    final proteinas = (resumen['proteinas_g'] ?? 0.0).toDouble();
    final carbohidratos = (resumen['carbohidratos_g'] ?? 0.0).toDouble();
    final grasas = (resumen['grasas_g'] ?? 0.0).toDouble();
    
    final metaP = (resumen['proteinas_objetivo'] ?? 150.0).toDouble();
    final metaC = (resumen['carbohidratos_objetivo'] ?? 250.0).toDouble();
    final metaG = (resumen['grasas_objetivo'] ?? 60.0).toDouble();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final balance = Provider.of<BalanceProvider>(context, listen: false);

    return RefreshIndicator(
      onRefresh: _loadBalance,
      color: const Color(0xFF1E88E5),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── PREMIUM HEADER ──
          SliverToBoxAdapter(
            child: _buildHeroHeader(consumidas, quemadas, objetivo, restantes),
          ),

          // ── MACRO PILLS ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: _buildMacroPills(proteinas, carbohidratos, grasas, metaP, metaC, metaG),
            ),
          ),

          // ── TABS ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF1565C0),
                  unselectedLabelColor: Colors.grey.shade400,
                  indicatorColor: const Color(0xFF1E88E5),
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Comidas'),
                    Tab(text: 'Ejercicios'),
                    Tab(text: 'Recetario'),
                  ],
                ),
              ),
            ),
          ),

          // ── CONTENT ──
          SliverFillRemaining(
            hasScrollBody: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAlimentosList(alimentos),
                  _buildEjerciciosList(ejercicios),
                  _buildRecetarioList(balance, auth),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(double consumidas, double quemadas, double objetivo, double restantes) {
    final progreso = objetivo > 0 ? (consumidas / objetivo).clamp(0.0, 1.5) : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.3, 0.9],
            colors: [
              const Color(0xFF1E88E5),
              const Color(0xFF1565C0),
            ],
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(35),
            bottomRight: Radius.circular(35),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withOpacity(0.4),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.assessment_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mi Balance',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1),
                        ),
                        if (_selectedDate != null && 
                            (_selectedDate!.day != DateTime.now().day || 
                             _selectedDate!.month != DateTime.now().month))
                          Text(
                            'Historial: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                            style: TextStyle(color: Colors.orange.shade200, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                      ),
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Color(0xFF1565C0), // header background color
                                  onPrimary: Colors.white, // header text color
                                  onSurface: Colors.black, // body text color
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                          _loadBalance();
                        }
                      },
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      ),
                      onPressed: _loadBalance,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Linear Progress (Compact)
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              restantes.toStringAsFixed(0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                letterSpacing: -1,
                              ),
                            ),
                            Text(
                              'kcal restantes',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${(progreso * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: LinearProgressIndicator(
                          value: progreso * _animController.value,
                          backgroundColor: Colors.white.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progreso > 1.0 ? Colors.orange.shade300 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildHeaderStat('Meta', objetivo.toStringAsFixed(0), Icons.flag_rounded),
                _buildVerticalDivider(),
                _buildHeaderStat('Comido', consumidas.toStringAsFixed(0), Icons.restaurant_rounded),
                _buildVerticalDivider(),
                _buildHeaderStat('Quemado', quemadas.toStringAsFixed(0), Icons.local_fire_department_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.6), size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(width: 1, height: 36, color: Colors.white.withOpacity(0.15));
  }

  // ═══════════════════════════════════════════
  // ██  MACRO PILLS (PREMIUM 2.0)
  // ═══════════════════════════════════════════
  
  Widget _buildMacroPills(double proteinas, double carbohidratos, double grasas, double metaP, double metaC, double metaG) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMacroPill(
                'Proteínas',
                proteinas,
                metaP,
                Icons.restaurant_menu_rounded,
                const Color(0xFFEF5350),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMacroPill(
                'Carbos',
                carbohidratos,
                metaC,
                Icons.bakery_dining_rounded,
                const Color(0xFFFFA726),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMacroPill(
                'Grasas',
                grasas,
                metaG,
                Icons.water_drop_rounded,
                const Color(0xFF42A5F5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMacroPill(String label, double value, double meta, IconData icon, Color color) {
    final double progress = meta > 0 ? (value / meta).clamp(0.0, 1.0) : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.05), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 12),
          Text(
            '${value.toStringAsFixed(0)}g',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.blueGrey.shade300,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ██  FOOD / EXERCISE LISTS
  // ═══════════════════════════════════════════

  Widget _buildAlimentosList(List alimentos) {
    if (alimentos.isEmpty) {
      return _buildEmptyTabState(
        'Sin alimentos registrados',
        Icons.restaurant_rounded,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: alimentos.length,
      itemBuilder: (context, index) => _buildAlimentoCard(alimentos[index], index),
    );
  }

  Widget _buildEjerciciosList(List ejercicios) {
    if (ejercicios.isEmpty) {
      return _buildEmptyTabState(
        'Sin ejercicio registrado',
        Icons.fitness_center_rounded,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: ejercicios.length,
      itemBuilder: (context, index) => _buildEjercicioCard(ejercicios[index], index),
    );
  }

  Widget _buildEmptyTabState(String mensaje, IconData icon) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 64, color: Colors.blue.withOpacity(0.3)),
              ),
              const SizedBox(height: 24),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ RECETARIO UI ============

  Widget _buildRecetarioList(BalanceProvider provider, AuthProvider auth) {
    return Consumer<BalanceProvider>(
      builder: (context, balanceProvider, _) {
        if (balanceProvider.isSuggestionsLoading && balanceProvider.suggestions.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final suggestions = balanceProvider.suggestions;

        if (suggestions.isEmpty) {
          return _buildEmptyTabState(
            'Tu recetario está vacío.\nGuarda recetas o rutinas desde el chat con la IA.',
            Icons.bookmark_border,
          );
        }

        return RefreshIndicator(
          onRefresh: () => balanceProvider.fetchSuggestions(auth.token!),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return _buildSuggestionCard(suggestion, balanceProvider, auth);
            },
          ),
        );
      },
    );
  }

  Widget _buildSuggestionCard(Suggestion item, BalanceProvider provider, AuthProvider auth) {
    final bool isComida = item.tipo == 'comida';
    final color = isComida ? Colors.orange : Colors.blue;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.05), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSuggestionDetail(item),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isComida 
                        ? [Colors.orange.shade400, Colors.orange.shade700]
                        : [Colors.blue.shade400, Colors.blue.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isComida ? Icons.restaurant_menu_rounded : Icons.fitness_center_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.macros,
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () => _confirmarEliminarSugerencia(item, provider, auth),
                    child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuggestionDetail(Suggestion item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.nombre,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E88E5)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.tipo == 'comida' ? Colors.orange.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.tipo.toUpperCase(),
                      style: TextStyle(
                        color: item.tipo == 'comida' ? Colors.orange.shade800 : Colors.blue.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.macros,
                style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Divider(height: 40),
              
              if (item.ingredientes.isNotEmpty) ...[
                const Text(
                  'Ingredientes / Equipo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...item.ingredientes.map((ing) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ing, style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                )),
                const SizedBox(height: 24),
              ],
              
              if (item.preparacion.isNotEmpty) ...[
                const Text(
                  'Instrucciones / Pasos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...item.preparacion.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFF1E88E5),
                        child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                )),
              ],
              
              if (item.nota.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nota IA:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const SizedBox(height: 4),
                      Text(item.nota, style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmarEliminarSugerencia(Suggestion item, BalanceProvider provider, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar del recetario?'),
        content: Text('¿Estás seguro de que quieres eliminar "${item.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await provider.deleteSuggestion(item.id, auth.token!);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Eliminado correctamente')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Error al eliminar')),
                );
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlimentoCard(Map<String, dynamic> alimento, int index) {
    final nombre = alimento['nombre'] ?? '';
    final hora = alimento['hora_registro'] ?? '';
    final freq = alimento['frecuencia_total'] ?? 1;
    final punt = (alimento['puntuacion'] ?? 0.0).toDouble();
    final horaCorta = hora.length >= 5 ? hora.substring(0, 5) : hora;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = (index * 0.1).clamp(0.0, 0.5);
        final anim = CurvedAnimation(
          parent: _animController,
          curve: Interval(delay, (delay + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
        );
        return Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: Opacity(opacity: anim.value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade300, Colors.orange.shade500],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMiniChip(Icons.local_fire_department_rounded, '${alimento['macros']?['calorias']?.toStringAsFixed(0) ?? 0}', Colors.orange),
                        const SizedBox(width: 6),
                        _buildMiniChip(null, 'P: ${alimento['macros']?['proteinas']?.toStringAsFixed(1) ?? 0}g', const Color(0xFFEF5350)),
                        const SizedBox(width: 6),
                        _buildMiniChip(null, 'C: ${alimento['macros']?['carbohidratos']?.toStringAsFixed(1) ?? 0}g', const Color(0xFFFFA726)),
                        const SizedBox(width: 6),
                        _buildMiniChip(null, 'G: ${alimento['macros']?['grasas']?.toStringAsFixed(1) ?? 0}g', const Color(0xFF42A5F5)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(horaCorta, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        if (freq > 1) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'x$freq',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                        if (punt > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade700),
                                const SizedBox(width: 2),
                                Text(
                                  punt.toStringAsFixed(1),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.amber.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _eliminarRegistro(alimento['id'], 'alimento'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 18),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEjercicioCard(Map<String, dynamic> ejercicio, int index) {
    final nombre = ejercicio['nombre'] ?? '';
    final hora = ejercicio['hora_registro'] ?? '';
    final freq = ejercicio['frecuencia_total'] ?? 1;
    final horaCorta = hora.length >= 5 ? hora.substring(0, 5) : hora;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = (index * 0.1).clamp(0.0, 0.5);
        final anim = CurvedAnimation(
          parent: _animController,
          curve: Interval(delay, (delay + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
        );
        return Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: Opacity(opacity: anim.value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade700],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildMiniChip(Icons.local_fire_department_rounded, '${ejercicio['calorias_quemadas']?.toStringAsFixed(0) ?? 0} kcal', Colors.orange),
                        const SizedBox(width: 8),
                        Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(horaCorta, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        if (freq > 1) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'x$freq',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _eliminarRegistro(ejercicio['id'], 'ejercicio'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ██  BOTTOM NAV
  // ═══════════════════════════════════════════

  Widget _buildMiniChip(IconData? icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.1), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      selectedIndex: 2,
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ChatScreen()));
        } else if (index == 3) {
          _navigateToProfile();
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Asistente'),
        NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Balance'),
        NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
      ],
    );
  }

  Future<void> _navigateToProfile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.userId == null || authProvider.token == null) return;

    try {
      final client = await _apiService.getClientProfile(authProvider.userId!, authProvider.token!);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (context) => EditProfileScreen(client: client)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al abrir perfil: $e')));
      }
    }
  }

  Widget _buildFABRegistro() {
    return FloatingActionButton(
      onPressed: _showRegistroOptions,
      backgroundColor: const Color(0xFF1E88E5),
      child: const Icon(Icons.add_rounded, color: Colors.white),
    );
  }

  void _showRegistroOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '¿Qué quieres registrar?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFF2563EB)),
              ),
              title: const Text('Registro de Comida', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Añade alimentos con macros calculados'),
              onTap: () async {
                Navigator.pop(ctx);
                await SmartMealRegistrySheet.show(context);
                if (mounted) _loadBalance();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Color(0xFF10B981)),
              ),
              title: const Text('Registrar Rutina', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Añade ejercicios y calcula calorías quemadas'),
              onTap: () async {
                Navigator.pop(ctx);
                await RoutineBuilderSheet.show(context);
                if (mounted) _loadBalance();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red.shade300),
            ),
            const SizedBox(height: 20),
            Text('Error de conexión', style: TextStyle(color: Colors.grey.shade800, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Error desconocido',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBalance,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
