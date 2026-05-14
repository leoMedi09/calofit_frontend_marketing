import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/assistant_response.dart';
import '../utils/assistant_message_format.dart';
import 'calorie_progress_card.dart';
import 'recipe_card.dart';
import 'workout_card.dart';

class AssistantMessageBubble extends StatelessWidget {
  final AssistantResponse response;
  final Function(String)? onAction;
  final Function(Section)? onSave; // Callback para guardar sugerencia

  const AssistantMessageBubble({Key? key, required this.response, this.onAction, this.onSave}) : super(key: key);

  /// Alinea badge/colores con tarjetas de comida: el backend a veces envía INFO
  /// con `secciones` de tipo comida; el front fuerza RECIPE para que no "salte" el tema.
  static String _displayIntent(AssistantResponse r) {
    final base = (r.intencion ?? 'INFO').toUpperCase();
    final tp = (r.tipoPregunta ?? '').toUpperCase();
    if (tp.contains('RECOMENDAR_NUTRICION') && base == 'INFO') {
      return 'RECIPE';
    }
    if (base == 'INFO' && r.respuestaEstructurada.secciones.any((s) => s.tipo == 'comida')) {
      return 'RECIPE';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAlert = response.alertaSalud == true;
    
    // v70.8: Temática basada en Intención
    final String intent = _displayIntent(response);
    final Map<String, dynamic> theme = _getIntentTheme(intent, hasAlert);
    final Color primaryColor = theme['color'];
    final IconData icon = theme['icon'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: primaryColor,
            child: Icon(
              icon,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Mostrar Progreso Calórico (Si aplica)
                if (response.dataCientifica.progresoDiario.isNotEmpty && 
                    (response.dataCientifica.progresoDiario['consumido'] ?? 0) > 0)
                  CalorieProgressMiniCard(data: response.dataCientifica.progresoDiario),

                // 2. El texto de la IA (Burbuja estilizada)
                Container(
                  padding: intent == 'RECIPE'
                      ? const EdgeInsets.fromLTRB(18, 18, 18, 20)
                      : const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme['bgColor'],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(
                      color: theme['borderColor'],
                      width: intent == 'DANGER' ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge superior de la categoría (Intención)
                      if (intent != 'CHAT' && intent != 'NORMAL')
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme['bgColor'] == Colors.white ? Colors.grey.shade50 : theme['bgColor'],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme['borderColor'],
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                theme['icon'],
                                size: 14,
                                color: theme['color'],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                theme['label'] ?? 'Información',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme['color'],
                                ),
                              ),
                            ],
                          ),
                        ),
                      MarkdownBody(
                        data: _cleanResponseText(
                          response.respuestaEstructurada.textoConversacional,
                          response.respuestaEstructurada.secciones,
                        ),
                        selectable: true, // Permitir copiar texto
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: theme['textColor'],
                            fontSize: 15,
                            height: 1.5,
                          ),
                          pPadding: const EdgeInsets.only(bottom: 6),
                          strong: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                          h2: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                            height: 1.35,
                          ),
                          h2Padding: const EdgeInsets.only(top: 12, bottom: 8),
                          h3: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme['textColor'],
                            height: 1.35,
                          ),
                          h3Padding: const EdgeInsets.only(top: 10, bottom: 6),
                          blockSpacing: 12,
                          listIndent: 26,
                          listBullet: TextStyle(
                            color: primaryColor.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.45,
                          ),
                          listBulletPadding:
                              const EdgeInsets.only(right: 10, top: 2),
                          // Estilo mejorado para tablas
                          tableHead: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                          tableBorder: TableBorder.all(color: Colors.grey.shade300, width: 1),
                          tableBody: const TextStyle(fontSize: 14),
                          blockquote: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(left: BorderSide(color: Colors.blue.shade300, width: 4)),
                            color: Colors.blue.shade50,
                          ),
                          code: TextStyle(
                            backgroundColor: Colors.grey.shade100,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Tarjetas de comida / ejercicio (separadas del Markdown para lectura clara)
                if (response.respuestaEstructurada.secciones.isNotEmpty)
                  const SizedBox(height: 10),
                ...response.respuestaEstructurada.secciones.map((sec) {
                  if (sec.tipo == 'comida') {
                    return RecipeCard(
                      section: sec,
                      onSave: onSave != null ? () => onSave!(sec) : null,
                    );
                  }
                  if (sec.tipo == 'ejercicio') {
                    return WorkoutCard(
                      section: sec,
                      onSave: onSave != null ? () => onSave!(sec) : null,
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),

                // 4. Advertencia Nutricional (Si existe)
                if (response.advertencia != null) 
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      "ℹ️ ${response.advertencia}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Si en un mismo renglón viene "texto ## Subtítulo", parte en dos bloques válidos para Markdown.
  static String _splitEmbeddedMarkdownHeadings(String line) {
    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith('#')) return line;
    if (!line.contains(RegExp(r'#{2,}\s'))) return line;
    final parts = line.split(RegExp(r'\s+(?=#{1,6}\s)'));
    if (parts.length < 2) return line;
    return parts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join('\n\n');
  }

  String _cleanResponseText(String text, List<Section> sections) {
    try {
      // 1. Eliminar etiquetas CALOFIT blindadas (apertura Y cierre)
      // v64: Regex más específico para no matar (X kcal) o (Macros: ...)
      String cleaned = text.replaceAll(RegExp(r'\[/?CALOFIT_(?:HEADER|LIST|ACTION|FOOTER|STATS|INTENT)(?:[:\s].*?)?\]'), '');

      // Marcadores tipo [Icon] que a veces envía el modelo
      cleaned = cleaned.replaceAll(RegExp(r'\[(?:Icon|icon|emoji)[^\]]*\]\s*'), '');
      // "##" en medio de la línea → el motor Markdown no lo trata como encabezado
      cleaned = cleaned
          .split('\n')
          .map(_splitEmbeddedMarkdownHeadings)
          .join('\n');

      // Viñetas • en un solo párrafo → lista Markdown (-) con saltos de línea
      cleaned = expandInlineBulletsForMarkdown(cleaned);

      // 2. Transformar Tablas Markdown en Listas Legibles (Verticales)
      if (RegExp(r'\|[\s-:]+\|').hasMatch(cleaned)) {
        cleaned = cleaned.replaceAll(RegExp(r'^.*\|[\s-:]+\|.*$', multiLine: true), '');
        List<String> lines = cleaned.split('\n');
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.contains('|')) {
            if (line.startsWith('|')) line = line.substring(1);
            if (line.endsWith('|')) line = line.substring(0, line.length - 1);
            List<String> cells = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
            if (cells.length >= 2) {
               String name = cells[0].replaceAll('**', '').replaceAll('*', '').trim();
               lines[i] = '* **$name**: ${cells.sublist(1).join(" | ")}';
            } else if (cells.length == 1) {
               String item = cells[0].trim();
               if (item.startsWith('*') || item.startsWith('-')) {
                 lines[i] = item;
               } else {
                 lines[i] = '* $item';
               }
            }
          }
        }
        cleaned = lines.join('\n');
      }
      
      // 4. ELIMINACIÓN AGRESIVA DE NOMBRES REPETIDOS
      List<String> lines = cleaned.split('\n');
      List<String> sectionNames = sections.map((s) => s.nombre.toLowerCase().replaceAll('**', '').trim()).toList();
      
      List<String> finalLines = [];
      for (String line in lines) {
        if (line.trim().isEmpty) {
          finalLines.add(line);
          continue;
        }

        String lineLower = line.toLowerCase();
        String lineClean = lineLower.replaceAll('**', '').replaceAll('*', '').replaceAll('-', '').trim();

        // No tratar como "título duplicado" las líneas con cantidades (evita borrar ingredientes
        // que mencionan parte del nombre del plato, p. ej. "80g arroz integral").
        final isFoodQuantityLine = RegExp(r'\d+\s*g\b', caseSensitive: false).hasMatch(line) ||
            RegExp(r'\d+\s*kcal', caseSensitive: false).hasMatch(line) ||
            RegExp(r'\d+\s*(?:ml|l)\b', caseSensitive: false).hasMatch(line);

        bool isRepeatedName = sectionNames.any((name) {
          if (name.isEmpty) return false;
          if (lineClean == name) return true;
          if (lineClean.contains(name) && lineClean.length <= name.length + 5) return true;
          if (name.length > 10 && lineClean.contains(name.substring(0, 10)) && lineClean.length < 50) {
            return true;
          }
          return false;
        });

        if (isFoodQuantityLine || !isRepeatedName) {
          finalLines.add(line);
        }
      }
      
      // Limpiar múltiples saltos de línea consecutivos
      String result = finalLines.join('\n').trim();
      return result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    } catch (e) {
      debugPrint("Error cleaning AI response: $e");
      return text;
    }
  }

  Map<String, dynamic> _getIntentTheme(String intent, bool hasAlert) {
    if (hasAlert || intent == 'DANGER') {
      return {
        'color': Colors.red.shade700,
        'bgColor': Colors.red.shade50,
        'borderColor': Colors.red.shade200,
        'textColor': Colors.red.shade900,
        'icon': Icons.warning_amber_rounded,
        'label': 'Aviso Importante',
      };
    }

    switch (intent) {
      case 'RECIPE':
        return {
          'color': Colors.orange.shade700,
          'bgColor': Colors.orange.shade50.withOpacity(0.4), // Fondo muy tenue pero distintivo
          'borderColor': Colors.orange.shade200,
          'textColor': Colors.black87,
          'icon': Icons.restaurant_menu_rounded,
          'label': 'Nutrición',
        };
      case 'POWER':
        return {
          'color': Colors.blue.shade700,
          'bgColor': Colors.blue.shade50.withOpacity(0.5), // Fondo deportivo
          'borderColor': Colors.blue.shade200,
          'textColor': Colors.black87,
          'icon': Icons.fitness_center_rounded,
          'label': 'Ejercicio',
        };
      case 'SUCCESS':
      case 'LOG':
        return {
          'color': Colors.green.shade700,
          'bgColor': Colors.green.shade50.withOpacity(0.5),
          'borderColor': Colors.green.shade200,
          'textColor': Colors.green.shade900,
          'icon': Icons.check_circle_rounded,
          'label': 'Registro',
        };
      case 'PROGRESS':
        return {
          'color': Colors.purple.shade600,
          'bgColor': Colors.purple.shade50.withOpacity(0.4),
          'borderColor': Colors.purple.shade200,
          'textColor': Colors.black87,
          'icon': Icons.insights_rounded,
          'label': 'Balance',
        };
      case 'INFO':
      default:
        return {
          'color': const Color(0xFF14B8A6),
          'bgColor': Colors.white,
          'borderColor': Colors.grey.shade200,
          'textColor': Colors.black87,
          'icon': Icons.lightbulb_rounded,
          'label': 'Asistente',
        };
    }
  }
}

