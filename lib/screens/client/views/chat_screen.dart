import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../models/client.dart';
import 'edit_profile_screen.dart';
import 'mi_balance_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../models/assistant_response.dart';
import '../../../widgets/chat_bubble.dart';
import '../../../providers/balance_provider.dart';
import '../widgets/smart_meal_registry_sheet.dart';
import '../widgets/routine_builder_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  final ApiService _apiService = ApiService();
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  /// Reconocimiento listo (initialize OK).
  bool _speechReady = false;
  /// Idioma instalado en el teléfono para dictado (es_MX, es_ES, …).
  String _speechLocaleId = 'es_ES';
  /// Evita callbacks viejos tras detener manualmente.
  int _speechSession = 0;
  /// Un solo envío por dictado (manual stop vs finalResult).
  bool _speechSubmitHandled = false;
  
  bool _isTyping = false;
  bool _isListening = false;
  bool _isKeyboardVisible = false;
  bool _isMuted = false; 
  String? _speakingMessageId; 
  Client? _clientProfile; 
  String? _latestFuzzyHint;
  bool _showHelpBanner = true;

  /// Si el usuario ya envió mensajes en esta sesión, no reemplazar la lista al terminar
  /// la carga asíncrona del historial (evita "borrar" el chat por condición de carrera).
  bool _chatSessionDirty = false;

  // 🔄 ONE-STREAM: Una sola lista de mensajes (ahora persistente)
  List<Map<String, dynamic>> _messages = [
    {
      'role': 'assistant',
      'response': AssistantResponse(
        usuario: '',
        dataCientifica: ScientificData(progresoDiario: {}),
        respuestaEstructurada: StructuredResponse(
          textoConversacional: '¡Hola! Soy CaloFit. 🤖\nPuedes preguntarme sobre nutrición o simplemente decirme "Comí arroz con pollo" para registrarlo.',
          secciones: []
        )
      ),
      'type': 'assistant_v3',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
    _focusNode.addListener(_onFocusChange);
    _loadClientProfile();
    _loadChatHistory();
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech onStatus: $status');
        // Algunos dispositivos dejan el estado "notListening/done" sin pasar por onResult.finalResult.
        // Esto evita que el UI se quede "escuchando" y que el TTS parezca apagado.
        final s = status.toLowerCase();
        if (mounted && (s.contains('notlistening') || s.contains('done'))) {
          setState(() => _isListening = false);
        }
      },
      onError: (e) {
        debugPrint('Speech onError: $e');
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voz: ${e.errorMsg}')),
          );
        }
      },
    );
    if (!ok) {
      debugPrint('Speech initialize failed (permiso o servicio no disponible)');
    }
    if (ok) {
      try {
        final locales = await _speech.locales();
        _speechLocaleId = _pickSpanishLocaleId(locales);
      } catch (_) {
        _speechLocaleId = 'es_ES';
      }
    }
    _speechReady = ok;
    if (mounted) setState(() {});
  }

  String _pickSpanishLocaleId(List<stt.LocaleName> locales) {
    final ids = locales.map((e) => e.localeId).toSet();
    const prefs = ['es_MX', 'es_ES', 'es_US', 'es_CO', 'es_AR', 'es_PE'];
    for (final p in prefs) {
      if (ids.contains(p)) return p;
    }
    for (final l in locales) {
      if (l.localeId.startsWith('es')) return l.localeId;
    }
    return locales.isNotEmpty ? locales.first.localeId : 'es_ES';
  }

  String _chatHistoryStorageKey(AuthProvider auth) {
    if (auth.userId != null) return 'chat_history_${auth.userId}';
    final e = auth.userEmail?.trim().toLowerCase();
    if (e != null && e.isNotEmpty) {
      final safe = e.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
      return 'chat_history_email_$safe';
    }
    return 'chat_history_default';
  }

  // ═══ PART A: Historial Persistente del Chat ═══
  Future<void> _loadChatHistory() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final key = _chatHistoryStorageKey(auth);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved != null) {
        final List decoded = jsonDecode(saved);
        final List<Map<String, dynamic>> loaded = [];
        for (final item in decoded) {
          if (item['type'] == 'assistant_v3' && item['response_json'] != null) {
            loaded.add({
              'role': 'assistant',
              'response': AssistantResponse.fromJson(item['response_json']),
              'type': 'assistant_v3',
            });
          } else if (item['type'] == 'registro_exitoso') {
            loaded.add({
              'role': item['role'] ?? 'assistant',
              'content': item['content'] ?? '',
              'type': 'registro_exitoso',
              'badge': item['badge'],
              'data': item['data'],
            });
          } else {
            loaded.add({
              'role': item['role'] ?? 'user',
              'content': item['content'] ?? '',
              'type': item['type'] ?? 'text',
            });
          }
        }
        if (loaded.isNotEmpty && mounted) {
          if (_chatSessionDirty) {
            return;
          }
          setState(() => _messages = loaded);
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error cargando historial: $e');
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final key = _chatHistoryStorageKey(auth);
      final prefs = await SharedPreferences.getInstance();

      // Serializar los últimos 50 mensajes
      final toSave = _messages.length > 50
          ? _messages.sublist(_messages.length - 50)
          : _messages;

      final serialized = toSave.map((msg) {
        if (msg['type'] == 'assistant_v3' && msg['response'] is AssistantResponse) {
          return {
            'type': 'assistant_v3',
            'role': 'assistant',
            'response_json': (msg['response'] as AssistantResponse).toMap(),
          };
        } else if (msg['type'] == 'registro_exitoso') {
          return {
            'type': 'registro_exitoso',
            'role': msg['role'],
            'content': msg['content'],
            'badge': msg['badge'],
            'data': msg['data'],
          };
        }
        return {
          'type': msg['type'] ?? 'text',
          'role': msg['role'],
          'content': msg['content'],
        };
      }).toList();

      await prefs.setString(key, jsonEncode(serialized));
    } catch (e) {
      debugPrint('Error guardando historial: $e');
    }
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text('¿Eliminar todas las conversaciones guardadas?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpiar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final key = _chatHistoryStorageKey(auth);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      setState(() {
        _chatSessionDirty = false;
        _messages = [
          {
            'role': 'assistant',
            'response': AssistantResponse(
              usuario: '',
              dataCientifica: ScientificData(progresoDiario: {}),
              respuestaEstructurada: StructuredResponse(
                textoConversacional: '¡Historial limpiado! 🧹 ¿En qué puedo ayudarte?',
                secciones: [],
              ),
            ),
            'type': 'assistant_v3',
          },
        ];
      });
    }
  }

  Future<void> _loadClientProfile() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.userId != null && auth.token != null) {
        final profile = await _apiService.getClientProfile(auth.userId!, auth.token!);
        if (mounted) setState(() => _clientProfile = profile);
      }
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
    }
  }

  void _onFocusChange() {
    setState(() => _isKeyboardVisible = _focusNode.hasFocus);
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("es-MX");
    await _flutterTts.setSpeechRate(0.55);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() => setState(() => _speakingMessageId = null));
  }

  // Se inicia bajo demanda para no molestar con permisos al abrir

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String content, String messageId) async {
    if (_speakingMessageId == messageId) {
      await _flutterTts.stop();
      setState(() => _speakingMessageId = null);
    } else {
      setState(() => _speakingMessageId = messageId);
      String plainText = content
          .replaceAll(RegExp(r'\*+'), '')
          .replaceAll(RegExp(r'#+'), '')
          .trim();
      await _flutterTts.speak(plainText);
    }
  }

  Future<void> _listen() async {
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo usar el micrófono. Revisa permisos en Ajustes → Apps → CaloFit → Permisos.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    if (!_isListening) {
      final session = ++_speechSession;
      _speechSubmitHandled = false;
      // Evitar conflicto audio focus: al escuchar, detenemos TTS (pero NO activamos mute).
      try {
        await _flutterTts.stop();
      } catch (_) {}
      if (mounted) setState(() => _speakingMessageId = null);
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (val) {
          if (!mounted || session != _speechSession) return;
          setState(() {
            _inputController.text = val.recognizedWords;
          });
          if (val.finalResult) {
            final text = val.recognizedWords.trim();
            if (_speechSubmitHandled) return;
            _speechSubmitHandled = true;
            setState(() => _isListening = false);
            _speech.stop();
            if (text.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 200), () {
                if (!mounted) return;
                _handleUnifiedSubmit(quickMessage: text);
              });
            }
          }
        },
        localeId: _speechLocaleId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } else {
      _speechSession++;
      final text = _inputController.text.trim();
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      if (text.isNotEmpty && !_speechSubmitHandled) {
        _speechSubmitHandled = true;
        _handleUnifiedSubmit(quickMessage: text);
      } else if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se captó texto. Habla cerca del mic o toca otra vez y dicta más fuerte.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 🧠 SMART ROUTING SYSTEM
  Future<void> _handleUnifiedSubmit({String? quickMessage}) async {
    final text = quickMessage ?? _inputController.text.trim();
    if (text.isEmpty) return;

    _chatSessionDirty = true;

    // Limpiamos el panel de escritura si enviamos texto normal 
    // o si el micrófono había rellenado este mismo texto en el panel.
    if (quickMessage == null || quickMessage == _inputController.text.trim()) {
      _inputController.clear();
    }

    // ═══ CALOFIT_REGISTER: Registro consistente desde card ═══
    if (text.startsWith('CALOFIT_REGISTER:')) {
      final consultaId = text.replaceFirst('CALOFIT_REGISTER:', '');
      setState(() => _isTyping = true);
      _scrollToBottom();

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final balance = Provider.of<BalanceProvider>(context, listen: false);
      final token = auth.token;
      if (token == null) return;

      try {
        final result = await _apiService.confirmarRegistroConId(consultaId, token);

        if (result['balance_actualizado'] != null) {
          balance.updateFromAssistant(result['balance_actualizado']);
          await balance.fetchFullBalance(token);
        }

        setState(() {
          _isTyping = false;
          _messages.add({
            'role': 'assistant',
            'content': result['mensaje'] ?? 'Registrado.',
            'type': 'registro_exitoso',
            'badge': 'comida',
            'data': result['balance_actualizado'],
          });
        });
        _saveChatHistory();
        _scrollToBottom();
      } catch (e) {
        setState(() {
          _isTyping = false;
          _messages.add({'role': 'assistant', 'content': 'Error al registrar: \$e', 'type': 'error'});
        });
        _saveChatHistory();
      }
      return;
    }

    // ═══ CALOFIT_WORKOUT: Flujo guiado (series/reps/peso) ═══
    if (text.startsWith('CALOFIT_WORKOUT:')) {
      final consultaId = text.replaceFirst('CALOFIT_WORKOUT:', '');
      setState(() => _isTyping = true);
      _scrollToBottom();

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token;
      if (token == null) return;

      try {
        final result = await _apiService.iniciarWorkoutConId(consultaId, token);
        final responseObj = AssistantResponse.fromJson(result);

        setState(() {
          _isTyping = false;
          _messages.add({
            'role': 'assistant',
            'response': responseObj,
            'type': 'assistant_v3',
          });
        });

        if (!_isMuted) _speak(responseObj.respuestaEstructurada.textoConversacional, "wk_${_messages.length}");
        _saveChatHistory();
        _scrollToBottom();
      } catch (e) {
        setState(() {
          _isTyping = false;
          _messages.add({'role': 'assistant', 'content': 'Error iniciando registro de entrenamiento: $e', 'type': 'error'});
        });
        _saveChatHistory();
      }
      return;
    }

    setState(() {
      _messages.add({'role': 'user', 'content': text, 'type': 'text'});
      _isTyping = true;
    });
    _scrollToBottom();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final balance = Provider.of<BalanceProvider>(context, listen: false);
    final token = auth.token;

    if (token == null) return;

    // Detectar Intención Simple (Heurística del lado del cliente para rapidez)
    final lowerText = text.toLowerCase();
    
    // Palabras detonantes de REGISTRO
    final logKeywords = [
      "comí", "comi", "almorzé", "almorcé", "cené", "desayuné", "tomé", "bebí", "ingerí",
      "registra", "anota", "apunta", "hice", "entrené", "corrí", "troté", "agregame", "clavé", "zampé",
      "me clavé", "me zampé", "me comí", "me tomé", "me bebí", "me comí", "me jalé",
      "sali", "salí", "fui", "correr", "caminar", "andar", "gym", "gimnasio", "pesas",
      "desayuné", "desayune", "almorcé", "almorce", "cené", "cene",
      "tuve", "tomi", "tomé un", "tomé una", "bebí un", "bebí una",
      "para el desayuno", "para el almuerzo", "para la cena",
      "en el desayuno", "en el almuerzo", "en la cena",
    ];

    bool isLogIntent = logKeywords.any((k) => lowerText.startsWith(k) || lowerText.contains(" $k ") || lowerText.contains("$k "));

    try {
      if (isLogIntent) {
        // 👉 RUTA REGISTRO (/log-inteligente)
        final result = await _apiService.registrarPorVoz(text, token);
        final bool ok = result['success'] != false;

        if (ok && result['balance_actualizado'] != null) {
          balance.updateFromAssistant(result['balance_actualizado']);
          // Actualización silenciosa de listas para la pantalla de Balance
          await balance.fetchFullBalance(token);
        }

        setState(() {
          _isTyping = false;
          if (!ok) {
            _messages.add({
              'role': 'assistant',
              'content': result['mensaje'] ?? 'No pude registrar. Intenta con más detalle.',
              'type': 'error',
            });
            if (!_isMuted) {
              _speak(result['mensaje']?.toString() ?? '', "reg_err_${_messages.length}");
            }
          } else {
            _messages.add({
              'role': 'assistant',
              'content': result['mensaje'] ?? 'Registrado.',
              'type': 'registro_exitoso', // Card visual solo si el backend confirma success
              'badge': result['tipo_detectado'],
              'data': result['datos'],
            });
            if (!_isMuted) _speak(result['mensaje'] ?? '', "reg_${_messages.length}");
          }
        });
        _saveChatHistory();

      } else {
        // 👉 RUTA CONSULTA (/consultar)
        // Construir historial reducido
        final history = _messages.length > 2 
          ? _messages.sublist(_messages.length > 6 ? _messages.length - 6 : 0, _messages.length - 1)
            .where((m) => m['type'] != 'registro_exitoso') // Filtrar logs puros del historial de chat
            .map((m) {
               String content = "";
               if (m['role'] == 'user') content = m['content'];
               else if (m['response'] is AssistantResponse) content = (m['response'] as AssistantResponse).respuestaEstructurada.textoConversacional;
               else content = m['content'] ?? "";
               return {'role': m['role'] == 'user' ? 'user' : 'assistant', 'content': content};
            }).toList() 
          : null;

        final result = await _apiService.consultarAsistente(text, token, historial: history);
        final responseObj = AssistantResponse.fromJson(result);
        
        // Actualizar datos si la consulta trajo progreso (ej: "¿cuánto me falta?")
        balance.updateFromAssistant(responseObj.dataCientifica.progresoDiario);

        setState(() {
          _isTyping = false;
          _latestFuzzyHint = result['control_adaptativo']?['mensaje_fuzzy'];
          _messages.add({
            'role': 'assistant',
            'response': responseObj,
            'type': 'assistant_v3'
          });

          // v21.1: Speech inteligente corregido
          String ttsText = responseObj.respuestaEstructurada.textoConversacional;
          if (responseObj.respuestaEstructurada.secciones.isNotEmpty) {
            final names = responseObj.respuestaEstructurada.secciones
                .map((s) => s.nombre.replaceAll('**', '').trim())
                .join(", ");
            ttsText = "${ttsText.split('.').first}. Te sugiero: $names";
          }
          
          if (!_isMuted) _speak(ttsText, "answ_${_messages.length}");
        });
        _saveChatHistory();
      }
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({'role': 'assistant', 'content': 'Ups, tuve un problema de conexión. 📡', 'type': 'error'});
      });
      _saveChatHistory();
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // Color de fondo más moderno (Gris azulado suave)
      appBar: _buildUnifiedAppBar(),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            if (_showHelpBanner) _buildHelpBanner(),
            Expanded(child: _buildMessageList()),
            
            if (_isTyping) _buildTypingIndicator(),
            // En landscape priorizamos el input y evitamos overflows por altura reducida.
            if (!_isTyping && !isLandscape) _buildQuickActions(),
            if (_isListening) _buildListeningBanner(),
            _buildInputArea(),
            if (!isLandscape) _buildStickyStatusBar(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  PreferredSizeWidget _buildUnifiedAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            child: const Icon(Icons.smart_toy_rounded, color: Colors.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Asistente CaloFit', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _latestFuzzyHint ?? 'En línea', 
                  style: TextStyle(color: Colors.green.shade600, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Botón limpiar historial
        IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.grey.shade400, size: 20),
          tooltip: 'Limpiar historial',
          onPressed: _clearChatHistory,
        ),
        if (_speakingMessageId != null)
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            tooltip: 'Detener voz',
            onPressed: () async {
              await _flutterTts.stop();
              setState(() => _speakingMessageId = null);
            },
          )
        else
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.grey.shade600),
            tooltip: _isMuted ? 'Activar voz' : 'Silenciar voz',
            onPressed: () => setState(() => _isMuted = !_isMuted),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: Colors.grey.shade200, height: 1),
      ),
    );
  }

  Widget _buildStickyStatusBar() {
    return Consumer<BalanceProvider>(
      builder: (context, provider, _) {
        final summary = provider.dailySummary;
        if (summary == null) return const SizedBox.shrink();
        
        final meta = summary.planObjetivo?.caloriasObjetivo ?? 2000;
        final restante = (meta - summary.calorias).clamp(0, meta);
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: const Color(0xFFE3F2FD),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_fire_department_rounded, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Text(
                "Restan ${restante.toStringAsFixed(0)} kcal hoy",
                style: TextStyle(color: Colors.blue.shade900, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      selectedIndex: 1,
      onDestinationSelected: (index) async {
        if (index == 0) {
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MiBalanceScreen()));
        } else if (index == 3) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (auth.userId == null || auth.token == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay una sesión activa.')));
            return;
          }
          try {
            final client = await _apiService.getClientProfile(auth.userId!, auth.token!);
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => EditProfileScreen(client: client)));
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al obtener perfil: $e')));
          }
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Asistente'), // Corrección aquí: label corregido de 'Asistente' a 'Chat' si se prefiere o dejarlo 'Asistente'
        NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Balance'),
        NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        
        if (msg['type'] == 'registro_exitoso') {
          return _buildRichLogCard(msg);
        } else if (msg['role'] == 'assistant' && msg['response'] is AssistantResponse) {
          return AssistantMessageBubble(
            response: msg['response'],
            onAction: (text) => _handleUnifiedSubmit(quickMessage: text),
            onSave: (section) async {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final token = auth.token;
              if (token == null) return;
              try {
                await _apiService.guardarSugerencia(
                  tipo: section.tipo,
                  nombre: section.nombre,
                  ingredientes: section.ingredientes,
                  preparacion: section.preparacion,
                  macros: section.macros,
                  nota: section.nota,
                  token: token,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🔖 "${section.nombre}" guardado en tu recetario'),
                      backgroundColor: Colors.blue.shade700,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al guardar: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          );
        } else if (msg['role'] == 'user') {
          return _buildUserBubble(msg['content']);
        }
        
        // Bubbles de texto simple (errores, etc)
        return _buildSimpleSystemBubble(msg['content'], isError: msg['type'] == 'error');
      },
    );
  }

  Widget _buildRichLogCard(Map<String, dynamic> msg) {
    // Tarjeta visual impactante para confirmación de registro
    final isFood = msg['badge'] == 'comida' || msg['badge'] == 'alimento'; // Ajustar según backend return
    final data = msg['data'] ?? {};
    final kcal = data['calorias'] ?? 0;
    
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280), // v69.1: Más ancho permitido para pantallas densas
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: isFood ? Colors.orange.shade100 : Colors.green.shade100, width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isFood ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(isFood ? Icons.restaurant_menu_rounded : Icons.directions_run_rounded, 
                      color: isFood ? Colors.orange : Colors.green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isFood ? "Comida Registrada" : "Ejercicio Registrado", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: isFood ? Colors.orange.shade800 : Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['calidad'] != null && isFood)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getQualityColor(data['calidad']),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          data['calidad'].toString().toUpperCase(),
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  Text(msg['content'], style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  if (kcal > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMiniStat(Icons.flash_on_rounded, "$kcal kcal", Colors.orange, isMain: true),
                        const SizedBox(height: 12),
                        
                        // 🔥 MACROS PRINCIPALES
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isFood && (data['proteinas_g'] ?? 0) > 0) 
                              _buildMiniStat(Icons.fitness_center_rounded, "${data['proteinas_g']}g Prot", Colors.red.shade400),
                            if (isFood && (data['carbohidratos_g'] ?? 0) > 0)
                              _buildMiniStat(Icons.grain_rounded, "${data['carbohidratos_g']}g Carb", Colors.orange.shade400),
                            if (isFood && (data['grasas_g'] ?? 0) > 0)
                              _buildMiniStat(Icons.water_drop_rounded, "${data['grasas_g']}g Gras", Colors.blue.shade400),
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // 🍭 MICROS (Azúcar, Fibra, Sodio) - Diseño más sutil
                        if (isFood) 
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                               if ((data['azucar_g'] ?? 0) > 0) 
                                 _buildMiniStat(Icons.icecream_rounded, "${data['azucar_g']}g Azú", Colors.purple.shade300, isMicro: true),
                               if ((data['fibra_g'] ?? 0) > 0)
                                 _buildMiniStat(Icons.eco_rounded, "${data['fibra_g']}g Fib", Colors.green.shade600, isMicro: true),
                               if ((data['sodio_mg'] ?? 0) > 0)
                                 _buildMiniStat(Icons.opacity_rounded, "${data['sodio_mg']}mg Sod", Colors.blueGrey.shade400, isMicro: true),
                            ],
                          ),
                      ],
                    )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMiniStat(IconData icon, String text, Color color, {bool isMain = false, bool isMicro = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isMain ? 16 : 14, color: color),
        const SizedBox(width: 4),
        Text(
          text, 
          style: TextStyle(
            fontSize: isMain ? 14 : (isMicro ? 11 : 12), 
            fontWeight: isMain ? FontWeight.bold : FontWeight.w600, 
            color: isMicro ? Colors.grey.shade600 : Colors.grey.shade800
          )
        )
      ],
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB), // Azul brillante moderno
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
            topRight: Radius.circular(4),
          ),
          boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 6, offset: const Offset(2, 4))],
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
    );
  }

  Widget _buildSimpleSystemBubble(String? text, {bool isError = false}) {
     return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isError ? Colors.red.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isError ? Colors.red.shade100 : Colors.grey.shade200),
        ),
        child: Text(text ?? '...', style: TextStyle(color: isError ? Colors.red.shade800 : Colors.black87)),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Procesando...', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildListeningBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Escuchando… Habla ahora. Lo que digas aparece arriba; toca el mic otra vez para enviar.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _quickChip("🍽️ ¿Qué como ahora?", "Dime qué puedo comer en este momento según mi plan."),
          _quickChip(
            "🏋️ ¿Qué ejercicio hago hoy?",
            "Dime qué ejercicios puedo hacer hoy según mi plan.",
          ),
          _quickChip("🍎 Registrar Comida", "He comido ", autofill: true),
          _quickChip("🏃 Registrar Ejercicio", "Hoy entrené ", autofill: true),
          _quickChip("📊 Mi Balance", "¿Cómo va mi progreso y macros de hoy?"),
        ],
      ),
    );
  }

  Widget _quickChip(String label, String message, {bool autofill = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: Colors.white,
        side: BorderSide(color: Colors.grey.shade300),
        shape: StadiumBorder(),
        onPressed: () {
          if (autofill) {
            _inputController.text = message;
            _focusNode.requestFocus();
          } else {
            _handleUnifiedSubmit(quickMessage: message);
          }
        },
      ),
    );
  }

  Future<void> _openManualLogDialog() async {
    final nombreCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final cCtrl = TextEditingController();
    final gCtrl = TextEditingController();
    final porcionCtrl = TextEditingController(text: "100");
    final categoriaCtrl = TextEditingController(text: "manual");
    final unidadCtrl = TextEditingController();
    final gramosUnidadCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Registro manual (etiqueta)"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombre (ej: Gaseosa)")),
                TextField(controller: kcalCtrl, decoration: const InputDecoration(labelText: "Calorías (por porción)"), keyboardType: TextInputType.number),
                Row(children: [
                  Expanded(child: TextField(controller: pCtrl, decoration: const InputDecoration(labelText: "P (g)"), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: cCtrl, decoration: const InputDecoration(labelText: "C (g)"), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: gCtrl, decoration: const InputDecoration(labelText: "G (g)"), keyboardType: TextInputType.number)),
                ]),
                TextField(controller: porcionCtrl, decoration: const InputDecoration(labelText: "Gramos por porción (ej: 500)"), keyboardType: TextInputType.number),
                TextField(controller: categoriaCtrl, decoration: const InputDecoration(labelText: "Categoría (ej: bebida/snack)")),
                Row(children: [
                  Expanded(child: TextField(controller: unidadCtrl, decoration: const InputDecoration(labelText: "Unidad opcional (botella/vaso)"))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: gramosUnidadCtrl, decoration: const InputDecoration(labelText: "g por unidad"), keyboardType: TextInputType.number)),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Registrar")),
          ],
        );
      },
    );

    if (res != true) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final balance = Provider.of<BalanceProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) return;

    double _d(String s) => double.tryParse(s.trim().replaceAll(",", ".")) ?? 0.0;

    setState(() => _isTyping = true);
    try {
      final result = await _apiService.registrarManualAlimento(
        nombre: nombreCtrl.text.trim(),
        calorias: _d(kcalCtrl.text),
        proteinasG: _d(pCtrl.text),
        carbohidratosG: _d(cCtrl.text),
        grasasG: _d(gCtrl.text),
        porcionG: _d(porcionCtrl.text),
        categoria: categoriaCtrl.text.trim().isEmpty ? "manual" : categoriaCtrl.text.trim(),
        unidad: unidadCtrl.text.trim().isEmpty ? null : unidadCtrl.text.trim(),
        gramosPorUnidad: gramosUnidadCtrl.text.trim().isEmpty ? null : _d(gramosUnidadCtrl.text),
        token: token,
      );

      final bool ok = result['success'] != false;
      if (ok && result['balance_actualizado'] != null) {
        balance.updateFromAssistant(result['balance_actualizado']);
        await balance.fetchFullBalance(token);
      }

      setState(() {
        _isTyping = false;
        if (!ok) {
          _messages.add({'role': 'assistant', 'content': result['mensaje'] ?? 'No pude registrar manual.', 'type': 'error'});
        } else {
          _messages.add({
            'role': 'assistant',
            'content': result['mensaje'] ?? 'Registrado.',
            'type': 'registro_exitoso',
            'badge': result['tipo_detectado'],
            'data': result['datos'],
          });
        }
      });
      _saveChatHistory();
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({'role': 'assistant', 'content': 'Error en registro manual: $e', 'type': 'error'});
      });
      _saveChatHistory();
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), // Reducido el padding inferior para conectar con el status bar
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: _listen, // Mantener presionado para hablar? No, tap to toggle better UX
            onTap: _listen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isListening ? Colors.red.shade100 : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, 
                color: _isListening ? Colors.red : Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () async {
              await SmartMealRegistrySheet.show(context);
              if (!mounted) return;
              final token = Provider.of<AuthProvider>(context, listen: false).token;
              if (token != null) await Provider.of<BalanceProvider>(context, listen: false).fetchFullBalance(token);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.restaurant_menu_rounded, color: Colors.orange.shade400),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () async {
              await RoutineBuilderSheet.show(context);
              if (!mounted) return;
              final token = Provider.of<AuthProvider>(context, listen: false).token;
              if (token != null) await Provider.of<BalanceProvider>(context, listen: false).fetchFullBalance(token);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.fitness_center_rounded, color: Colors.green.shade500),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: 'Escribe o di "Comí..."',
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _handleUnifiedSubmit(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _handleUnifiedSubmit(),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF2563EB),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Color _getQualityColor(dynamic quality) {
    if (quality == null) return Colors.grey;
    final q = quality.toString().toLowerCase();
    if (q.contains('alta')) return Colors.green;
    if (q.contains('media')) return Colors.orange;
    if (q.contains('baja')) return Colors.red;
    return Colors.grey;
  }
  Widget _buildHelpBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '💡 Tip: Usa el micrófono o escribe "Comí un pan con pollo" para registrar tus comidas, o pregúntame "¿Qué me recomiendas cenar?".',
              style: TextStyle(color: Colors.blue.shade900, fontSize: 12, height: 1.3),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showHelpBanner = false),
            child: Icon(Icons.close, color: Colors.blue.shade300, size: 18),
          )
        ],
      ),
    );
  }
}
