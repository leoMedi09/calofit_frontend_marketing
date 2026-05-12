import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // Configuración centralizada de URLs por plataforma

  static String get baseUrl {
    if (kIsWeb) {
      // Para Flutter Web
      return 'http://localhost:8000';
    } else if (Platform.isAndroid) {
      // Para dispositivo físico Android usa la IP de tu red Wi-Fi:
      return 'http://192.168.18.28:8000';
    } else if (Platform.isIOS) {
      // Para iOS Simulator
      return 'http://localhost:8000';
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // Para apps de escritorio
      return 'http://localhost:8000';
    }

    // Fallback por defecto
    return 'http://localhost:8000';
  }

  // 🌐 URLs alternativas para diferentes entornos
  static const String devUrl = 'http://localhost:8000';
  static const String prodUrl =
      'https://api.calofit.com'; // Cuando tengas producción

  // 📱 Para dispositivos físicos Android, usa la IP de tu máquina
  // Ejemplo: static const String physicalDeviceUrl = 'http://192.168.1.100:8000';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 120);

  // 🔍 Función de ayuda para debugging
  static void printCurrentConfig() {
    if (kDebugMode) {
      print('🌐 API Base URL: $baseUrl');
      print('📱 Platform: ${_getPlatformName()}');
    }
  }

  static String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
