import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PointsView extends StatefulWidget {
  const PointsView({Key? key}) : super(key: key);

  @override
  State<PointsView> createState() => _PointsViewState();
}

class _PointsViewState extends State<PointsView> {
  int _points = 0;
  late Timer _refreshTimer;

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

  Widget _buildProgress(String label, int min, int max, Color color, IconData icon) {
  final clampedPoints = _points.clamp(min, max);
  final progress = (clampedPoints - min) / (max - min);

  return Card(
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
              Text(
                '${clampedPoints - min}/${max - min} pts',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 12,
              color: color,
              backgroundColor: color.withOpacity(0.2),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Progreso de Nivel')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Puntos actuales: $_points',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _buildProgress('Medalla de Bronce', 0, 100, Colors.brown, Icons.emoji_events),
          _buildProgress('Medalla de Plata', 0, 300, Colors.grey, Icons.emoji_events),
          _buildProgress('Medalla de Oro', 0, 2500, Colors.amber, Icons.emoji_events),
          _buildProgress('Medalla Morada', 0, 4000, Colors.purple, Icons.star),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('points', 0);
              setState(() {
                _points = 0;
              });
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reiniciar puntos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
}
