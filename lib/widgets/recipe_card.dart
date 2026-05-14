import 'package:flutter/material.dart';
import '../models/assistant_response.dart';
import 'assistant_text_helpers.dart';

class RecipeCard extends StatelessWidget {
  final Section section;
  final VoidCallback? onSave;

  const RecipeCard({Key? key, required this.section, this.onSave})
      : super(key: key);

  static String _fmtMacroGrams(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  /// Si el backend envía [MacrosNormalizados] con algún valor > 0, chips/panel desde números (más estable que parsear el string).
  Map<String, String> _macrosMapForSection(Section section) {
    final n = section.macrosNormalizados;
    if (n != null && n.hasUsableMacros) {
      final m = <String, String>{};
      if (n.kcal > 0) m['Cal'] = '${_fmtMacroGrams(n.kcal)}kcal';
      if (n.proteinasG > 0) m['P'] = '${_fmtMacroGrams(n.proteinasG)}g';
      if (n.carbohidratosG > 0) m['C'] = '${_fmtMacroGrams(n.carbohidratosG)}g';
      if (n.grasasG > 0) m['G'] = '${_fmtMacroGrams(n.grasasG)}g';
      if (m.isNotEmpty) return m;
    }
    return _parseMacros(section.macros);
  }

  /// Quita emojis/símbolos del rótulo antes de mapear (el LLM a veces envía `🥚 P: 21g` y `lk.startsWith('p')` fallaba).
  static String _macroKeyLettersOnly(String raw) {
    return raw
        .replaceAll(
          RegExp(r'[^a-zA-ZñÑáéíóúüÁÉÍÓÚÜ0-9\s\-\.]'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Parsea "P: 9.4g | C: 18.4g | G: 15.2g | Cal: 350kcal" → Map
  Map<String, String> _parseMacros(String macros) {
    final result = <String, String>{};
    if (macros.isEmpty) return result;
    
    // v66: Estrategia de Split Ultra-Robusta
    // 1. Normalizar separadores: Reemplazar '|' y ';' por comas
    String text = macros.replaceAll('|', ',').replaceAll(';', ',');
    
    // 2. Proteger decimales (ej: 30,5 -> 30.5) temporalmente para no partir por la coma
    // Buscamos coma entre dos números
    text = text.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
    
    // 3. Ahora sí, partir por comas con confianza
    for (final pair in text.split(',')) {
      final parts = pair.trim().split(':');
      if (parts.length >= 2) {
        String key = parts[0].trim();
        final lk = _macroKeyLettersOnly(key).toLowerCase();
        // Mapeo flexible: abreviaturas y palabras completas (español). "Cal" antes que "C" suelto.
        if (lk.contains('kcal') ||
            lk.contains('calor') ||
            lk.contains('energ') ||
            lk == 'cal' ||
            lk.startsWith('cal ')) {
          key = 'Cal';
        } else if (lk.contains('prote')) {
          key = 'P';
        } else if (lk.contains('carb') || lk == 'carbos') {
          key = 'C';
        } else if (lk.contains('grasa') ||
            lk == 'lipidos' ||
            lk == 'lípidos' ||
            lk == 'grasas') {
          key = 'G';
        } else if (lk.startsWith('p') && lk.length <= 2) {
          key = 'P';
        } else if (lk.startsWith('c') && lk.length <= 2) {
          key = 'C';
        } else if (lk.startsWith('g') && lk.length <= 2) {
          key = 'G';
        } else {
          continue;
        }
        
        // El valor es el resto, volviendo a poner la coma si se prefiere (o dejar el punto)
        String val = parts.sublist(1).join(':').trim();
        // Limpiar comentarios entre paréntesis
        val = val.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        result[key] = val;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final macrosMap = _macrosMapForSection(section);
    final hasMacros = macrosMap.isNotEmpty;
    final hasSubtitle = hasMacros ||
        section.macros.isNotEmpty ||
        onSave != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.shade900.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.orange.shade50, shape: BoxShape.circle),
          child: const Icon(Icons.restaurant_menu,
              color: Colors.orange, size: 20),
        ),
        title: Text(
          section.nombre.replaceAll('**', '').trim().toUpperCase(),
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: hasSubtitle
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasMacros) _MacroChipsRow(macrosMap: macrosMap),
                    if (!hasMacros && section.macros.isNotEmpty)
                      Text(section.macros,
                          style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    if (onSave != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (onSave != null)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.bookmark_add,
                                  size: 18, color: Colors.blue),
                              label: const Text('Guardar',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              onPressed: onSave,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel detallado de macros al expandir
          if (hasMacros) ...[
            _MacroDetailPanel(macrosMap: macrosMap),
            const SizedBox(height: 16),
          ],

          if (section.ingredientes.isNotEmpty) ...[
            _sectionHeader('INGREDIENTES', Icons.shopping_basket),
            const SizedBox(height: 8),
            ..._ingredientListWidgets(section.ingredientes),
          ],
          if (section.ingredientes.isNotEmpty && section.preparacion.isNotEmpty)
            const Divider(height: 32),
          if (section.preparacion.isNotEmpty) ...[
            _sectionHeader('PREPARACIÓN', Icons.list),
            const SizedBox(height: 8),
            ..._preparacionListWidgets(section.preparacion),
          ],
          if (section.ingredientes.isEmpty && section.preparacion.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'No se recibió el detalle de ingredientes o pasos en esta respuesta.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ),

          if (section.nota.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.nota,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.orange.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _ingredientListWidgets(List<String> ingredientes) {
    final accent = Colors.orange;
    final w = <Widget>[];
    for (final raw in expandItemLines(ingredientes)) {
      if (isAssistantSubheader(raw)) {
        w.add(assistantSubheaderLine(
          stripMarkdownLight(raw),
          accent,
          isFirst: w.isEmpty,
        ));
      } else {
        w.add(_ingredientLine(stripMarkdownLight(raw), accent));
      }
    }
    return w;
  }

  /// Widget especializado para una línea de ingrediente.
  /// Parsea el string del backend y muestra:
  ///   • nombre principal (con gramos o medida)   [kcal badge]
  ///     ~Xg (si viene de medida doméstica)
  ///
  /// Formatos que maneja:
  ///   "200g pechuga de pollo (330 kcal)"
  ///   "1 cucharada (~15g) aceite de oliva (132.6 kcal)"
  ///   "150g platano maduro (133.5 kcal)"
  Widget _ingredientLine(String text, Color accent) {
    // Extraer kcal del último paréntesis: "(132.6 kcal)" o "(~15g | 132.6 kcal)"
    final reKcal = RegExp(
        r'\((?:~[\d.]+g\s*\|\s*)?([\d.]+)\s*kcal\)\s*$',
        caseSensitive: false);
    final mKcal = reKcal.firstMatch(text);
    String kcalStr = '';
    String nameRaw = text;
    if (mKcal != null) {
      kcalStr = mKcal.group(1) ?? '';
      nameRaw = text.substring(0, mKcal.start).trim();
    }

    // Extraer equivalencia en gramos: "(~15g)" o "(~15g |"
    final reGram = RegExp(r'\((~[\d.]+g)\)', caseSensitive: false);
    final mGram = reGram.firstMatch(nameRaw);
    String gramEquiv = '';
    if (mGram != null) {
      gramEquiv = mGram.group(1) ?? '';
      nameRaw = nameRaw.replaceFirst(reGram, '').trim();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text('•',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: accent.withValues(alpha: 0.6))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nameRaw,
                    style:
                        const TextStyle(fontSize: 13, height: 1.35)),
                if (gramEquiv.isNotEmpty)
                  Text(gramEquiv,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          height: 1.3)),
              ],
            ),
          ),
          if (kcalStr.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$kcalStr kcal',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _preparacionListWidgets(List<String> pasos) {
    final accent = Colors.orange;
    final flat = expandItemLines(pasos);
    final substantive =
        flat.where((r) => !isAssistantSubheader(r)).toList();
    final singleStep = substantive.length == 1;

    final w = <Widget>[];
    var stepIndex = 0;
    for (final raw in flat) {
      if (isAssistantSubheader(raw)) {
        w.add(assistantSubheaderLine(
          stripMarkdownLight(raw),
          accent,
          isFirst: w.isEmpty,
        ));
      } else {
        stepIndex++;
        final line = stripMarkdownLight(raw);
        if (singleStep) {
          w.add(assistantBulletLine(line, accent));
        } else {
          w.add(_stepRow(stepIndex, line, accent));
        }
      }
    }
    return w;
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
              letterSpacing: 1.1)),
    ]);
  }

  Widget _stepRow(int index, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$index.',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chips compactos de macros (visibles sin expandir)
// ─────────────────────────────────────────────────────────────────────────────
class _MacroChipsRow extends StatelessWidget {
  final Map<String, String> macrosMap;
  const _MacroChipsRow({required this.macrosMap});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [
      if (macrosMap.containsKey('Cal'))
        _chip('🔥 ${macrosMap['Cal']}', Colors.orange.shade700,
            Colors.orange.shade50),
      if (macrosMap.containsKey('P'))
        _chip('💪 P: ${macrosMap['P']}', Colors.blue.shade700,
            Colors.blue.shade50),
      if (macrosMap.containsKey('C'))
        _chip('🌾 C: ${macrosMap['C']}', Colors.amber.shade800,
            Colors.amber.shade50),
      if (macrosMap.containsKey('G'))
        _chip('🥑 G: ${macrosMap['G']}', Colors.green.shade700,
            Colors.green.shade50),
    ]);
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel detallado de macros (visible al expandir)
// ─────────────────────────────────────────────────────────────────────────────
class _MacroDetailPanel extends StatelessWidget {
  final Map<String, String> macrosMap;
  const _MacroDetailPanel({required this.macrosMap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.deepOrange.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Encabezado
        Row(children: [
          Icon(Icons.analytics_outlined, size: 14, color: Colors.orange.shade800),
          const SizedBox(width: 6),
          Text('INFORMACIÓN NUTRICIONAL',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                  letterSpacing: 1.0)),
        ]),
        const SizedBox(height: 12),

        // Calorías (tarjeta grande) + macros (barras)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (macrosMap.containsKey('Cal')) ...[
            _CalCard(calories: macrosMap['Cal']!),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(children: [
              if (macrosMap.containsKey('P'))
                _MacroRow('Proteína', macrosMap['P']!,
                    Colors.blue.shade400, Icons.fitness_center),
              if (macrosMap.containsKey('C'))
                _MacroRow('Carbos', macrosMap['C']!,
                    Colors.amber.shade600, Icons.grain),
              if (macrosMap.containsKey('G'))
                _MacroRow('Grasas', macrosMap['G']!,
                    Colors.green.shade500, Icons.water_drop),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _CalCard extends StatelessWidget {
  final String calories;
  const _CalCard({required this.calories});

  @override
  Widget build(BuildContext context) {
    final numStr = calories.replaceAll('kcal', '').trim();
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🔥', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(numStr,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('kcal',
            style: TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MacroRow(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ),
      ]),
    );
  }
}
