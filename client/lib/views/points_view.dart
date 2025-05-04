import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PointsView extends StatefulWidget {
  const PointsView({super.key});

  @override
  State<PointsView> createState() => _PointsViewState();
}

class _PointsViewState extends State<PointsView> {
  int _points = 0;
  late Timer _refreshTimer;

  final Map<String, bool> _expandedStates = {
    'Bronce': false,
    'Plata': false,
    'Oro': false,
    'Morada': false,
  };

  @override
  void initState() {
    super.initState();
    _loadPoints();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _loadPoints();
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _points = prefs.getInt('points') ?? 0;
    });
  }

  Widget _buildExpandableProgressCard({
    required String id,
    required String label,
    required int min,
    required int max,
    required Color color,
    required IconData icon,
    required List<String> achievements,
  }) {
    final clampedPoints = _points.clamp(min, max);
    final progress = (clampedPoints - min) / (max - min);
    final isExpanded = _expandedStates[id] ?? false;

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedStates[id] = !isExpanded;
        });
      },
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${clampedPoints - min}/${max - min} pts',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 12,
                        color: color,
                        backgroundColor: color.withOpacity(0.2),
                      ),
                    ),
                  );
                },
              ),
              if (isExpanded) ...[
                const SizedBox(height: 16),
                ...achievements.map(
                  (achievement) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            achievement,
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progreso de Nivel')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Puntos actuales: $_points',
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),

              _buildExpandableProgressCard(
                id: 'Bronce',
                label: 'Medalla de Bronce',
                min: 0,
                max: 100,
                color: Colors.brown,
                icon: Icons.emoji_events,
                achievements: [
                  'Has ganado tus primeros puntos',
                  'Primer escaneo BLE completado',
                  'Participaste en una misión',
                ],
              ),
              _buildExpandableProgressCard(
                id: 'Plata',
                label: 'Medalla de Plata',
                min: 100,
                max: 300,
                color: Colors.grey,
                icon: Icons.emoji_events,
                achievements: [
                  '10 escaneos completados',
                  'Alcanzaste los 200 pts',
                ],
              ),
              _buildExpandableProgressCard(
                id: 'Oro',
                label: 'Medalla de Oro',
                min: 300,
                max: 1000,
                color: Colors.amber,
                icon: Icons.emoji_events,
                achievements: [
                  'Máquina de escanear',
                  '500 pts alcanzados',
                  'Modo experto desbloqueado',
                ],
              ),
              _buildExpandableProgressCard(
                id: 'Morada',
                label: 'Medalla Morada',
                min: 1000,
                max: 2500,
                color: Colors.purple,
                icon: Icons.star,
                achievements: [
                  'Gran Maestro BLE',
                  'Leyenda del escaneo',
                  'Todos los niveles completados',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
