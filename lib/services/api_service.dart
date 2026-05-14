import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../models/auth.dart';
import '../models/user.dart';
import '../models/client.dart';
import '../models/exercise.dart';
import '../models/nutrition_plan.dart';
import '../config/api_config.dart';

class ApiService {
  static bool _needsLogout = false;
  
  // Estado global de sesion expirada.
  static bool get needsLogout => _needsLogout;
  
  // Limpia el flag despues de procesar logout en UI.
  static void resetLogoutFlag() {
    _needsLogout = false;
  }
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    headers: {'Content-Type': 'application/json'},
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
  ))..interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      // Evita cache de baseUrl durante hot reload.
      options.baseUrl = ApiConfig.baseUrl; 
      
      // Logging de peticiones.
      ApiConfig.printCurrentConfig();
      print('📤 ${options.method} ${options.baseUrl}${options.path}');
      return handler.next(options);
    },
    onError: (DioException e, handler) {
      final statusCode = e.response?.statusCode;
      final path = e.requestOptions.path;
      print('❌ Error en petición [${statusCode ?? 'SIN CÓDIGO'}]: ${e.message}');
      
      // Token invalido/expirado: solo para requests autenticadas.
      if (statusCode == 401 || statusCode == 403) {
        final hasAuthHeader = e.requestOptions.headers.containsKey('Authorization');
        final isAuthEndpoint = path.contains('/auth/login') || 
                               path.contains('/auth/register') ||
                               path.contains('/clientes/registrar') ||
                               path.contains('/forgot-password');
        
        // No cerrar sesion por errores de endpoints publicos.
        if (hasAuthHeader && !isAuthEndpoint) {
          print('🔐 Token inválido o expirado en petición autenticada. Cerrando sesión...');
          _needsLogout = true;
        } else {
          print('⚠️ Error 401/403 en endpoint público (credenciales incorrectas, no token expirado)');
        }
      }
      
      return handler.next(e);
    },
  ));

  // Autenticacion
  Future<LoginResponse> login(LoginRequest request) async {
    try {
      print('📤 Enviando datos de login: ${request.toJson()}');
      final response = await _dio.post('/auth/login', data: request.toJson());
      print('📥 Respuesta del servidor: ${response.data}');
      return LoginResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ Error en login: ${e.type} - ${e.message}');
      if (e.response != null) {
        print('   Detalle: ${e.response?.data}');
        throw Exception(e.response?.data['detail'] ?? 'Error en el servidor');
      }
      throw Exception('Error de conexión: ${e.type}');
    }
  }


  // Registro de Cliente
  Future<void> registerClient(ClientRegisterRequest request) async {
    try {
      final response = await _dio.post('/clientes/registrar', data: request.toJson());
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error al registrar cliente');
      }
    } catch (e) {
      print('Error en registro: $e');
      throw Exception('Error en registro: $e');
    }
  }

  // Registro de Staff (Admin/Nutri/Coach)
  Future<void> registerStaff(Map<String, dynamic> staffData, String token) async {
    try {
      print('📤 Registrando nuevo personal: ${staffData['email']}');
      final response = await _dio.post(
        '/usuarios/registrar', 
        data: staffData,
        options: Options(headers: {'Authorization': 'Bearer $token'})
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error al registrar personal');
      }
      print('✅ Personal registrado exitosamente');
    } on DioException catch (e) {
      print('❌ Error en registro de staff: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error al registrar personal');
    }
  }

  // ✅ Subir Foto de Perfil (Modular)
  Future<String> uploadProfilePicture(String token, String filePath, bool isStaff) async {
    try {
      final String endpoint = isStaff ? '/usuarios/perfil/foto' : '/clientes/perfil/foto';
      print('📤 Subiendo foto a $endpoint desde $filePath');
      
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.post(
        endpoint,
        data: formData,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/form-data',
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Foto subida exitosamente: ${response.data['url']}');
        return response.data['url'];
      } else {
        throw Exception('Error al subir la foto: ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('❌ Error Dio al subir foto: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error al conectar con el servidor');
    }
  }
  
  // ✅ CAMBIO DE CONTRASEÑA
  Future<void> changePassword(String token, String newPassword, String confirmPassword) async {
    try {
      final response = await _dio.post(
        '/auth/change-password',
        data: {
          'new_password': newPassword,
          'confirm_password': confirmPassword
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Error al cambiar contraseña');
      }
    } on DioException catch (e) {
      print('❌ Error en cambio de contraseña: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error al cambiar contraseña');
    }
  }

  // Usuarios
  Future<List<User>> getUsers(String token) async {
    try {
      final response = await _dio.get('/admin/staff',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return (response.data as List).map((json) => User.fromJson(json)).toList();
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error obteniendo usuarios: $errorMessage');
    } catch (e) {
      throw Exception('Error obteniendo usuarios: $e');
    }
  }
  
  // ✅ Obtener perfil del personal (Nutri/Coach/Admin)
  Future<Map<String, dynamic>> getStaffProfile(String token) async {
    try {
      print('🔍 Obteniendo perfil de staff...');
      final response = await _dio.get('/usuarios/me',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      
      print('✅ Perfil de staff obtenido: ${response.data}');
      return response.data;
    } catch (e) {
      print('❌ Error obteniendo perfil de staff: $e');
      throw Exception('Error obteniendo perfil de staff: $e');
    }
  }

  // Clientes
  
  // ✅ Crear Cliente Express (Nutricionista)
  Future<Map<String, dynamic>> createExpressClient(
    String email,
    String dni,
    String token, {
    int? assignedCoachId,
  }) async {
    try {
      final body = <String, dynamic>{
        'email': email.trim(),
        'dni': dni.trim(),
        if (assignedCoachId != null) 'assigned_coach_id': assignedCoachId,
      };
      final response = await _dio.post(
        '/nutricionista/clientes/express',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error creando cliente express: $e');
    }
  }

  // ✅ Lista de entrenadores activos (para asignar al crear paciente)
  Future<List<Map<String, dynamic>>> getCoachesList(String token) async {
    try {
      final response = await _dio.get(
        '/nutricionista/coaches',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      return [];
    }
  }

  // ✅ Guardar nota del entrenador en el expediente del cliente
  Future<void> saveCoachNote(int clientId, String note, String token) async {
    await _dio.put(
      '/nutricionista/cliente/$clientId/nota-entrenador',
      data: {'nota': note},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<List<Client>> getClients(String token) async {
    try {
      final response = await _dio.get('/clientes/',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return (response.data as List).map((json) => Client.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error obteniendo clientes: $e');
    }
  }

  // ✅ Obtener perfil del cliente (token JWT)
  Future<Client> getClientProfile(int clientId, String token) async {
    try {
      print('🔍 Obteniendo perfil del cliente...');
      final response = await _dio.get('/clientes/perfil',
          options: Options(headers: {'Authorization': 'Bearer $token'}));

      print('✅ Perfil del cliente obtenido: ${response.data}');
      return Client.fromJson(response.data);
    } catch (e) {
      print('❌ Error obteniendo perfil del cliente: $e');
      throw Exception('Error obteniendo perfil del cliente: $e');
    }
  }

  // ✅ Check-in Semanal
  Future<Map<String, dynamic>> getCheckInStatus(String token) async {
    try {
      final response = await _dio.get(
        '/clientes/checkin-status',
        options: Options(headers: {'Authorization': 'Bearer $token'})
      );
      return response.data;
    } on DioException catch (e) {
      print('❌ Error obteniendo status de check-in: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error de conexión');
    }
  }

  Future<void> postCheckIn(String token, Map<String, dynamic> data) async {
    try {
      await _dio.post(
        '/clientes/checkin',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'})
      );
    } on DioException catch (e) {
      print('❌ Error enviando check-in: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error al guardar check-in');
    }
  }

  // ✅ Actualizar contraseña de un miembro del staff (Admin only)
  Future<void> updateStaffPassword(int userId, String newPassword, String token) async {
    try {
      final response = await _dio.put(
        '/admin/staff/$userId/password',
        data: {'new_password': newPassword},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al actualizar contraseña');
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error: $errorMessage');
    }
  }

  // ✅ Actualizar datos de un miembro del staff (Admin only)
  Future<void> updateStaff(int userId, Map<String, dynamic> staffData, String token) async {
    try {
      print('📤 Actualizando datos de staff ID: $userId');
      final response = await _dio.put(
        '/admin/staff/$userId',
        data: staffData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al actualizar personal');
      }
      print('✅ Datos de staff actualizados exitosamente');
    } on DioException catch (e) {
      print('❌ Error al actualizar staff: ${e.response?.data}');
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error: $errorMessage');
    }
  }

  // ✅ Obtener logs de auditoría (Admin only)
  Future<List<Map<String, dynamic>>> getAdminLogs(String token) async {
    try {
      final response = await _dio.get('/admin/logs',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error: $errorMessage');
    }
  }

  // ✅ Actualizar perfil del cliente
  Future<void> updateClient(int clientId, Client client, String token) async {
    try {
      // Usamos el método toJson del modelo que ya incluye birth_date correctamente
      final Map<String, dynamic> updateData = client.toJson();

      print('📤 Actualizando perfil del cliente...');
      print('📤 Datos: $updateData');

      final response = await _dio.put('/clientes/perfil',
          data: updateData,
          options: Options(headers: {'Authorization': 'Bearer $token'}));

      print('✅ Perfil del cliente actualizado: ${response.data}');

      if (response.statusCode != 200) {
        throw Exception('Error al actualizar perfil');
      }
    } catch (e) {
      print('❌ Error al actualizar cliente: $e');
      throw Exception('Error al actualizar cliente: $e');
    }
  }

  // Ejercicios
  Future<List<Exercise>> getExercises(String token) async {
    try {
      final response = await _dio.get('/ejercicios/',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return (response.data as List).map((json) => Exercise.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error obteniendo ejercicios: $e');
    }
  }

  // Nutrición
  Future<List<NutritionPlan>> getNutritionPlans(String token) async {
    try {
      final response = await _dio.get('/nutricion/',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return (response.data as List).map((json) => NutritionPlan.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error obteniendo planes nutricionales: $e');
    }
  }

  // Asistente IA
  Future<String> askAssistant(String question, String token) async {
    try {
      final response = await _dio.post('/asistente/consultar',
          data: {'message': question},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data['response'] ?? response.data['answer'] ?? 'Sin respuesta';
    } catch (e) {
      throw Exception('Error consultando asistente: $e');
    }
  }

  Future<Map<String, dynamic>> getSugerenciaEstrategica(int clientId, String token) async {
    try {
      final response = await _dio.get(
        '/nutricionista/cliente/$clientId/sugerir-estrategia',
        options: Options(headers: {'Authorization': 'Bearer $token'})
      );
      return response.data;
    } catch (e) {
      throw Exception('Error al obtener sugerencia de la IA: $e');
    }
  }

  // ============ ENDPOINTS DASHBOARD ============

  Future<Map<String, dynamic>> getDailySummary(int clientId, String token) async {
    try {
      final response = await _dio.get('/dashboard/clientes/$clientId/resumen-diario',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error obteniendo resumen diario: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCaloriesTrend(int clientId, String token) async {
    try {
      final response = await _dio.get('/dashboard/clientes/$clientId/calorias-tendencia',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw Exception('Error obteniendo tendencia de calorías: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getWeightHistory(int clientId, String token) async {
    try {
      final response = await _dio.get('/dashboard/clientes/$clientId/peso-historial',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw Exception('Error obteniendo historial de peso: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getIMCHistory(int clientId, String token) async {
    try {
      final response = await _dio.get('/dashboard/clientes/$clientId/imc-historial',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw Exception('Error obteniendo historial de IMC: $e');
    }
  }

  Future<Map<String, dynamic>> getAIAnalysis(int clientId, String token) async {
    try {
      final response = await _dio.get('/dashboard/clientes/$clientId/analisis-ia',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      print('⚠️ Error en análisis IA: $e');
      return {}; // Retornar mapa vacío evita que la App explote
    }
  }

  // app/lib/services/api_service.dart

  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    try {
      final response = await _dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      print('✅ Código solicitado: ${response.data}');
      return response.data;
    } on DioException catch (e) {
      print('❌ Error al solicitar código: ${e.response?.data}');
      throw Exception(e.response?.data['detail'] ?? 'Error al solicitar el código');
    }
  }

  Future<Map<String, dynamic>> verifyResetCode(String email, String code) async {
    try {
      final response = await _dio.post(
        '/auth/verify-reset-code',
        data: {
          'email': email,
          'reset_code': code,
          'new_password': '', // No se usa en este paso
        },
      );
      return {'success': true, 'message': response.data['message']};
    } on DioException catch (e) {
      return {'success': false, 'message': e.response?.data['detail'] ?? 'Error al validar el código'};
    }
  }

  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    try {
      final response = await _dio.post(
        '/auth/reset-password',
        data: {
          'email': email,
          'reset_code': code,
          'new_password': newPassword,
        },
      );
      return {'success': true, 'message': response.data['message']};
    } on DioException catch (e) {
      return {'success': false, 'message': e.response?.data['detail'] ?? 'Error al actualizar contraseña'};
    }
  }

  /// 🍽️ Obtiene el plan nutricional/dieta de un cliente por su Firebase UID
  Future<Map<String, dynamic>> getDietaPorUid(String firebaseUid, String token) async {
    try {
      print('🔍 Buscando dieta automática para UID: $firebaseUid');
      final response = await _dio.get('/clientes/por-uid/$firebaseUid',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      print('❌ Error obteniendo dieta por UID: $e');
      throw Exception('Error al conectar con el servicio de dietas');
    }
  }

  // ============ SISTEMA DE RECOMENDACIONES PERSONALIZADAS ============

  /// 🧠 Obtiene recomendaciones personalizadas según preferencias del usuario
  /// - Usuario nuevo: Top alimentos populares según objetivo
  /// - Usuario con historial: Sus favoritos aprendidos
  Future<Map<String, dynamic>> getRecomendacionesPersonalizadas(String token) async {
    try {
      print('🔍 Obteniendo recomendaciones personalizadas...');
      final response = await _dio.get('/nutricion/recomendaciones',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Recomendaciones obtenidas: ${response.data}');
      return response.data;
    } catch (e) {
      print('❌ Error obteniendo recomendaciones: $e');
      throw Exception('Error obteniendo recomendaciones: $e');
    }
  }

  // ============ MI BALANCE DIARIO ============

  /// 📊 Obtiene el balance calórico de un día específico (por defecto, hoy)
  /// Incluye: resumen, alimentos registrados, ejercicios registrados
  Future<Map<String, dynamic>> getMiBalance(String token, {String? fecha}) async {
    try {
      print('🔍 Obteniendo balance del día ${fecha ?? "hoy"}...');
      final queryParams = fecha != null ? {'fecha': fecha} : null;
      final response = await _dio.get('/balance/hoy',
          queryParameters: queryParams,
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Balance obtenido: ${response.data}');
      return response.data;
    } catch (e) {
      print('❌ Error obteniendo balance: $e');
      throw Exception('Error obteniendo balance: $e');
    }
  }

  /// 🗑️ Elimina un registro de alimento o ejercicio
  /// tipo: "alimento" o "ejercicio"
  /// Recalcula automáticamente el balance después de eliminar
  Future<Map<String, dynamic>> eliminarRegistro(int registroId, String tipo, String token) async {
    try {
      print('🗑️ Eliminando registro ID: $registroId, tipo: $tipo');
      final response = await _dio.delete('/balance/registro/$registroId',
          queryParameters: {'tipo': tipo},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Registro eliminado: ${response.data}');
      return response.data;
    } catch (e) {
      print('❌ Error eliminando registro: $e');
      throw Exception('Error eliminando registro: $e');
    }
  }

  // ============ DETALLE DE ALIMENTOS CON IA ============

  /// 🍎 Obtiene información nutricional completa de un alimento usando Groq IA
  /// Genera: datos nutricionales, recomendaciones, porciones comunes, alternativas saludables
  Future<Map<String, dynamic>> getDetalleAlimento(String alimento, int porcionGramos, String token) async {
    try {
      print('🔍 Obteniendo detalle de: $alimento ($porcionGramos g)');
      final response = await _dio.post('/alimentos/detalle',
          data: {
            'alimento': alimento,
            'porcion_gramos': porcionGramos
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Detalle obtenido: ${response.data['nombre']}');
      return response.data;
    } catch (e) {
      print('❌ Error obteniendo detalle de alimento: $e');
      throw Exception('Error obteniendo detalle de alimento: $e');
    }
  }

  // ============ SMART MEAL REGISTRY (CARRITO) ============

  /// 🛒 Parsea una cadena de ingredientes usando IA y devuelve los macros calculados
  Future<Map<String, dynamic>> parseIngredients(String texto, String token) async {
    try {
      print('🛒 Parseando ingredientes: "$texto"');
      final response = await _dio.post('/api/v1/nutrition/parse_ingredients',
          data: {'texto': texto},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } on DioException catch (e) {
      final msg = e.response?.data != null ? e.response!.data.toString() : e.message;
      print('❌ Error parseando ingredientes: $msg');
      throw Exception('Error: $msg');
    } catch (e) {
      print('❌ Error parseando ingredientes: $e');
      throw Exception('Error: $e');
    }
  }

  // ============ ROUTINE BUILDER ============

  Future<Map<String, dynamic>> calcularEjercicioManual(String texto, String token) async {
    try {
      final response = await _dio.post('/asistente/calcular-ejercicio',
          data: {'texto': texto},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error al calcular ejercicio: $e');
    }
  }

  Future<Map<String, dynamic>> registrarRutinaManual(List<Map<String, dynamic>> ejercicios, String token) async {
    try {
      final response = await _dio.post('/asistente/log-rutina-manual',
          data: {'ejercicios': ejercicios},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error al registrar rutina manual: $e');
    }
  }

  // ============ REGISTRO INTELIGENTE POR VOZ/TEXTO (NLP) ============

  /// 🎤 Registra alimentos o ejercicios usando lenguaje natural
  /// Ejemplo: "Comí arroz con pollo" → Extrae automáticamente macros
  /// Sistema aprende preferencias automáticamente
  Future<Map<String, dynamic>> registrarPorVoz(String mensaje, String token) async {
    try {
      print('🎤 Registrando por voz: "$mensaje"');
      final response = await _dio.post('/asistente/log-inteligente',
          data: {'mensaje': mensaje},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Registro exitoso: ${response.data}');
      return response.data;
    } catch (e) {
      print('❌ Error en registro por voz: $e');
      throw Exception('Error en registro por voz: $e');
    }
  }

  // ============ REGISTRO MANUAL (ETIQUETA / MULTIMODAL) ============
  Future<Map<String, dynamic>> registrarManualAlimento({
    required String nombre,
    required double calorias,
    required double proteinasG,
    required double carbohidratosG,
    required double grasasG,
    required double porcionG,
    String categoria = "manual",
    String? unidad,
    double? gramosPorUnidad,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/asistente/log-manual',
        data: {
          'nombre': nombre,
          'calorias': calorias,
          'proteinas_g': proteinasG,
          'carbohidratos_g': carbohidratosG,
          'grasas_g': grasasG,
          'porcion_g': porcionG,
          'categoria': categoria,
          'unidad': unidad,
          'gramos_por_unidad': gramosPorUnidad,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      throw Exception('Error en registro manual: $e');
    }
  }

  /// ✅ Confirma registro usando consulta_id (valores exactos de la card)
  Future<Map<String, dynamic>> confirmarRegistroConId(String consultaId, String token) async {
    try {
      print('✅ Confirmando registro con consulta_id: $consultaId');
      final response = await _dio.post('/asistente/confirmar-registro',
          data: {'consulta_id': consultaId},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      print('❌ Error en confirmar registro: $e');
      throw Exception('Error al confirmar registro: $e');
    }
  }

  /// 🏋️ Inicia flujo guiado de fuerza (series/reps/peso) desde una card de ejercicio
  Future<Map<String, dynamic>> iniciarWorkoutConId(String consultaId, String token) async {
    try {
      print('🏋️ Iniciando workout con consulta_id: $consultaId');
      final response = await _dio.post(
        '/asistente/iniciar-workout',
        data: {'consulta_id': consultaId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      print('❌ Error iniciando workout: $e');
      throw Exception('Error al iniciar workout: $e');
    }
  }

  /// 🔖 Guarda una sugerencia (receta/rutina) de la IA para después
  Future<Map<String, dynamic>> guardarSugerencia({
    required String tipo,
    required String nombre,
    required List<String> ingredientes,
    required List<String> preparacion,
    required String macros,
    required String nota,
    required String token,
  }) async {
    try {
      final response = await _dio.post('/asistente/guardar-sugerencia',
          data: {
            'tipo': tipo,
            'nombre': nombre,
            'ingredientes': ingredientes,
            'preparacion': preparacion,
            'macros': macros,
            'nota': nota,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error al guardar sugerencia: $e');
    }
  }

  /// 📋 Lista las sugerencias guardadas del usuario
  Future<List<dynamic>> listarSugerencias(String token) async {
    try {
      final response = await _dio.get('/asistente/mis-sugerencias',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error al listar sugerencias: $e');
    }
  }

  /// 🗑️ Elimina una sugerencia guardada
  Future<void> eliminarSugerencia(int id, String token) async {
    await _dio.delete('/asistente/sugerencia/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}));
  }

  /// 💬 Consulta al asistente IA con control adaptativo (fuzzy logic)
  /// El tono del asistente se adapta según adherencia y progreso.
  /// Se envía el historial para mantener el contexto de la conversación.
  Future<Map<String, dynamic>> consultarAsistente(String mensaje, String token, {List<Map<String, dynamic>>? historial, Map<String, dynamic>? datosReales}) async {
    try {
      final payload = {
        'mensaje': mensaje,
        if (historial != null) 'historial': historial,
        if (datosReales != null) 'datos_reales': datosReales,
      };

      // 🔍 LOG DE PREGUNTA (v1.1)
      debugPrint('--- 🤖 IA REQUEST START ---');
      debugPrint('Payload: ${jsonEncode(payload)}');
      debugPrint('--- 🤖 IA REQUEST END ---');

      // El backend puede tardar (prompt + Groq hasta ~GROQ_TIMEOUT_SEC); evitar corte prematuro del cliente.
      final response = await _dio.post('/asistente/consultar',
          data: payload,
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            receiveTimeout: const Duration(seconds: 210),
          ));

      // 🔍 LOG DE RESPUESTA (v1.1)
      debugPrint('--- 📬 IA RESPONSE START ---');
      debugPrint(jsonEncode(response.data));
      debugPrint('--- 📬 IA RESPONSE END ---');

      return response.data;
    } on DioException catch (e) {
      debugPrint('❌ Error consultando asistente: ${e.message}');
      if (e.response != null) {
        debugPrint('Respuesta error: ${jsonEncode(e.response?.data)}');
      }
      throw Exception('Error consultando asistente: $e');
    }
  }

  /// 🩺 Consulta al Copiloto Clínico (Staff)
  /// Nueva ruta aislada para nutricionistas y admins.
  Future<Map<String, dynamic>> consultarCopiloto(String mensaje, String token, {List<Map<String, dynamic>>? historial}) async {
    try {
      final payload = {
        'mensaje': mensaje,
        if (historial != null) 'historial': historial,
      };

      debugPrint('🩺 >>> PETICIÓN COPILOTO CLÍNICO <<<');
      final response = await _dio.post('/copiloto/consultar',
          data: payload,
          options: Options(headers: {'Authorization': 'Bearer $token'}));

      return response.data;
    } on DioException catch (e) {
      debugPrint('❌ Error en Copiloto: ${e.message}');
      throw Exception('Error en Copiloto: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  // ============ ALERTAS DE SALUD (STAFF) ============

  /// 🚨 Obtiene alertas de salud de los clientes asignados (solo staff)
  Future<List<Map<String, dynamic>>> getMisAlertasClientes(String token) async {
    try {
      print('🔍 Obteniendo alertas de clientes...');
      final response = await _dio.get('/alertas/mis-clientes',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ ${response.data.length} alertas obtenidas');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      print('❌ Error obteniendo alertas: $e');
      throw Exception('Error obteniendo alertas: $e');
    }
  }

  /// 📋 Obtiene detalle de una alerta específica
  Future<Map<String, dynamic>> getDetalleAlerta(int alertaId, String token) async {
    try {
      final response = await _dio.get('/alertas/$alertaId',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return response.data;
    } catch (e) {
      throw Exception('Error obteniendo detalle de alerta: $e');
    }
  }

  /// ✅ Marca una alerta como atendida y agrega notas
  Future<void> atenderAlerta(int alertaId, String notas, String token) async {
    try {
      print('✅ Atendiendo alerta ID: $alertaId');
      await _dio.put('/alertas/$alertaId/atender',
          data: {'notas': notas},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Alerta atendida exitosamente');
    } catch (e) {
      print('❌ Error atendiendo alerta: $e');
      throw Exception('Error atendiendo alerta: $e');
    }
  }

  /// 📝 Actualiza una alerta existente
  Future<void> actualizarAlerta(int alertaId, Map<String, dynamic> data, String token) async {
    try {
      await _dio.put('/alertas/$alertaId/actualizar',
          data: data,
          options: Options(headers: {'Authorization': 'Bearer $token'}));
    } catch (e) {
      throw Exception('Error actualizando alerta: $e');
    }
  }

  /// 🔍 Obtiene alertas de un cliente específico (staff)
  Future<List<Map<String, dynamic>>> getAlertasCliente(int clienteId, String token) async {
    try {
      final response = await _dio.get('/alertas/cliente/$clienteId',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw Exception('Error obteniendo alertas del cliente: $e');
    }
  }

  /// ✅ Suspender o reactivar miembro del staff (Admin only)
  Future<void> updateStaffStatus(int userId, String token) async {
    try {
      final response = await _dio.put(
        '/admin/staff/$userId/status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al cambiar el estado del staff');
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error: $errorMessage');
    }
  }


  /// ✅ Eliminar permanentemente miembro del staff (Admin only)
  Future<void> deleteStaff(int userId, String token) async {
    try {
      final response = await _dio.delete(
        '/admin/staff/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al eliminar personal');
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map ? e.response?.data['detail'] : e.message;
      throw Exception('Error: $errorMessage');
    }
  }

  // ============ PANEL NUTRICIONISTA (Phase 2) ============

  /// 🏥 Obtiene la lista de clientes asignados al nutricionista/admin
  Future<List<Map<String, dynamic>>> getNutricionistaClientes(String token) async {
    try {
      print('🔍 Obteniendo pacientes asignados...');
      final response = await _dio.get('/nutricionista/clientes',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } on DioException catch (e) {
      String errorMessage = e.message ?? 'Error desconocido';
      if (e.response?.data is Map) {
        errorMessage = e.response?.data['detail'] ?? errorMessage;
      } else if (e.response?.data is String) {
        errorMessage = e.response?.statusMessage ?? 'Error del servidor (500)';
      }
      throw Exception('Error obteniendo pacientes: $errorMessage');
    }
  }

  /// 🎯 Actualiza la guía estratégica (foco, recomendados, prohibidos) del cliente (staff)
  Future<void> actualizarGuiaEstrategica(int clienteId, Map<String, dynamic> data, String token) async {
    try {
      print('🎯 Actualizando guía estratégica para cliente $clienteId...');
      await _dio.post('/nutricionista/actualizar-guia-estrategica/$clienteId',
          data: data,
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      print('✅ Guía estratégica actualizada');
    } on DioException catch (e) {
      print('❌ Error actualizando guía: ${e.response?.data}');
      throw Exception('Error actualizando guía: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// 📊 Obtiene estadísticas clave para el dashboard del nutricionista
  Future<Map<String, dynamic>> getNutriStats(String token) async {
    try {
      print('🔍 Obteniendo estadísticas de nutricionista...');
      final response = await _dio.get('/nutricionista/stats',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw Exception('Error al obtener estadísticas: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// 📈 Obtiene el progreso histórico (peso/imc) de un paciente específico
  Future<Map<String, dynamic>> getNutricionistaClienteProgreso(int clienteId, String token) async {
    try {
      final response = await _dio.get('/nutricionista/cliente/$clienteId/progreso',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      String errorMessage = e.message ?? 'Error desconocido';
      if (e.response?.data is Map) {
        errorMessage = e.response?.data['detail'] ?? errorMessage;
      } else if (e.response?.data is String) {
        errorMessage = e.response?.statusMessage ?? 'Internal Server Error';
      }
      throw Exception('Error obteniendo progreso: $errorMessage');
    }
  }

  /// ✅ Valida el plan nutricional de un paciente
  Future<void> validarPlanPaciente(int clienteId, String token) async {
    try {
      await _dio.post('/nutricionista/validar-plan/$clienteId',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
    } on DioException catch (e) {
      String errorMessage = e.message ?? 'Error desconocido';
      if (e.response?.data is Map) {
        errorMessage = e.response?.data['detail'] ?? errorMessage;
      } else if (e.response?.data is String) {
        errorMessage = e.response?.statusMessage ?? 'Internal Server Error';
      }
      throw Exception('Error validando plan: $errorMessage');
    }
  }

  /// 🔗 Asigna especialistas (nutri/coach) a un cliente (Admin only)
  Future<void> assignEspecialista(int clienteId, {int? nutriId, int? trainerId, required String token}) async {
    try {
      await _dio.put(
        '/admin/clientes/$clienteId/asignar',
        queryParameters: {
          if (nutriId != null) 'nutri_id': nutriId,
          if (trainerId != null) 'trainer_id': trainerId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception('Error al asignar especialistas: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// 👥 Obtiene la lista de todo el staff (Admin only)
  Future<List<Map<String, dynamic>>> getStaffList(String token) async {
    try {
      final response = await _dio.get('/admin/staff',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return List<Map<String, dynamic>>.from(response.data);
    } on DioException catch (e) {
      throw Exception('Error al obtener staff: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// 🍱 Obtiene el plan nutricional detallado de un paciente
  Future<Map<String, dynamic>> getPatientPlan(int clienteId, String token) async {
    try {
      final response = await _dio.get('/nutricionista/cliente/$clienteId/plan',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw Exception('Error al obtener plan: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// 📝 Actualiza el plan nutricional de un paciente
  Future<void> updatePatientPlan(int clienteId, Map<String, dynamic> planData, String token) async {
    try {
      await _dio.put('/nutricionista/cliente/$clienteId/plan',
          data: planData,
          options: Options(headers: {'Authorization': 'Bearer $token'}));
    } on DioException catch (e) {
      throw Exception('Error al actualizar plan: ${e.response?.data['detail'] ?? e.message}');
    }
  }

  /// Crea un cliente mínimo desde el panel Admin.
  /// Solo email + contraseña + firebase_uid. El resto lo completa el cliente en el Onboarding.
  Future<void> adminCreateClient({
    required String email,
    required String password,
    required String flutterUid,
    required String token,
    int? assignedNutriId,
    int? assignedCoachId,
  }) async {
    try {
      await _dio.post(
        '/clientes/admin-crear',
        data: {
          'email': email,
          'password': password,
          'flutter_uid': flutterUid,
          if (assignedNutriId != null) 'assigned_nutri_id': assignedNutriId,
          if (assignedCoachId != null) 'assigned_coach_id': assignedCoachId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception('Error al crear cliente: ${e.response?.data?['detail'] ?? e.message}');
    }
  }

  /// Elimina permanentemente un cliente (BD + Firebase Auth)
  Future<void> deleteClient(int clientId, String token) async {
    try {
      await _dio.delete(
        '/nutricionista/cliente/$clientId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['detail'] ?? 'Error al eliminar el cliente.');
    }
  }
}

// Exception simple para manejo de errores
class HTTPException implements Exception {
  final int code;
  final String message;
  HTTPException(this.code, this.message);
  @override
  String toString() => 'HTTP $code: $message';
}
