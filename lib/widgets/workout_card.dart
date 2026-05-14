import 'package:flutter/material.dart';
import '../models/assistant_response.dart';
import 'assistant_text_helpers.dart';

class WorkoutCard extends StatelessWidget {
  final Section section;
  final VoidCallback? onSave;

  const WorkoutCard({Key? key, required this.section, this.onSave})
      : super(key: key);

  String get _nombreLimpio => section.nombre.replaceAll('**', '').trim();

  @override
  Widget build(BuildContext context) {
    final circuito = _circuitoListWidgets(section.ingredientes);
    final instrucciones = _instruccionesListWidgets(section.preparacion);
    final hayCircuito = circuito.isNotEmpty;
    final hayInstrucciones = instrucciones.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade900.withOpacity(0.04),
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
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.fitness_center, color: Colors.blue, size: 20),
        ),
        title: Text(
          _nombreLimpio.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.local_fire_department,
                        size: 14, color: Colors.red),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      section.macros.trim().isEmpty
                          ? 'Gasto según duración e intensidad'
                          : section.macros,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                ],
              ),
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
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        onPressed: onSave,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('TÉCNICA Y PASOS', Icons.accessibility_new),
          const SizedBox(height: 8),
          if (hayInstrucciones) ...instrucciones else _cajaVaciaInstrucciones(),
          const Divider(height: 28),
          _sectionHeader('MÚSCULO, EQUIPO Y VOLUMEN', Icons.list_alt),
          const SizedBox(height: 8),
          if (hayCircuito) ...circuito else _cajaVaciaCircuito(),
          const SizedBox(height: 16),
          if (section.nota.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: Colors.blue.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.nota,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.blue.shade900,
                        fontSize: 12.5,
                        height: 1.4,
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

  Widget _cajaVaciaCircuito() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        'Aquí irían series, repeticiones, peso o tiempo. Vuelve a preguntar al asistente: '
        '«detalla series y repeticiones de $_nombreLimpio».',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800),
      ),
    );
  }

  Widget _cajaVaciaInstrucciones() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        'Sin descripción paso a paso en esta respuesta. Pide al asistente: '
        '«explica la técnica de $_nombreLimpio paso a paso».',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800),
      ),
    );
  }

  List<Widget> _circuitoListWidgets(List<String> ejercicios) {
    const accent = Colors.blue;
    final w = <Widget>[];
    for (final raw in expandItemLines(ejercicios)) {
      if (isAssistantSubheader(raw)) {
        w.add(assistantSubheaderLine(
          stripMarkdownLight(raw),
          accent,
          isFirst: w.isEmpty,
        ));
      } else {
        w.add(assistantBulletLine(stripMarkdownLight(raw), accent));
      }
    }
    return w;
  }

  List<Widget> _instruccionesListWidgets(List<String> pasos) {
    const accent = Colors.blue;
    final w = <Widget>[];
    var stepIndex = 0;
    for (final raw in expandItemLines(pasos)) {
      if (isAssistantSubheader(raw)) {
        w.add(assistantSubheaderLine(
          stripMarkdownLight(raw),
          accent,
          isFirst: w.isEmpty,
        ));
      } else {
        stepIndex++;
        w.add(_stepRow(stepIndex, stripMarkdownLight(raw), accent));
      }
    }
    return w;
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _stepRow(int index, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
