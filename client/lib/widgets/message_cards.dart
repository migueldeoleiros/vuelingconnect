import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/string_utils.dart';
import '../utils/date_utils.dart';

class FlightCard extends StatelessWidget {
  final Map<String, dynamic> flight;
  final bool isExpanded;
  final VoidCallback? onTap;

  const FlightCard({
    super.key,
    required this.flight,
    this.isExpanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Validate required fields exist with reasonable defaults
    final flightNumber = flight['flight_number'] ?? 'Unknown';
    final flightStatus = flight['flight_status'] ?? 'unknown';
    final flightMessage = flight['flight_message'] ?? 'No message available';
    final timestamp = flight['timestamp'] ?? DateTime.now().toIso8601String();
    final source = flight['source'] ?? 'api';
    final isBluetoothSource = source == 'bluetooth';
    final String? eta = flight['eta']; // ETA may not be available

    final cardContent = Card(
      elevation: 4,
      margin: isExpanded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Flight $flightNumber',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (isBluetoothSource)
                  const Tooltip(
                    message: 'Received via Bluetooth',
                    child: Icon(Icons.bluetooth, color: Colors.blue, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${capitalizeFirstLetter(flightStatus)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: getStatusColor(flightStatus),
              ),
            ),
            // Show ETA if available and status is not "arrived" or "cancelled"
            if (eta != null &&
                flightStatus != 'arrived' &&
                flightStatus != 'cancelled') ...[
              const SizedBox(height: 8),
              Text(
                'ETA: ${formatDateTime(eta)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(flightMessage),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last Updated: ${formatDateTime(timestamp)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isBluetoothSource)
                  const Text(
                    'BLE',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (isExpanded) {
      return SizedBox(width: double.infinity, child: cardContent);
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: cardContent);
    }

    return cardContent;
  }
}

class AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback? onTap;

  const AlertCard({super.key, required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Validate required fields exist with reasonable defaults
    final alertType = alert['alert_type'];
    final message = alert['message'] ?? 'No message available';
    final timestamp = alert['timestamp'] ?? DateTime.now().toIso8601String();
    final source = alert['source'] ?? 'api';
    final isBluetoothSource = source == 'bluetooth';

    return Card(
      elevation: 4,
      color: getAlertColor(alertType).withOpacity(0.2),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(getAlertIcon(alertType), color: getAlertColor(alertType)),
        title: Row(
          children: [
            Text(
              capitalizeFirstLetter(alertType),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (isBluetoothSource)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.bluetooth, color: Colors.blue, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (isBluetoothSource)
              const Text(
                'Received via Bluetooth',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: Text(
          formatDateTime(timestamp).split(' ')[1], // Just show time
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: onTap ?? () => _showAlertDialog(context, alert),
      ),
    );
  }

  void _showAlertDialog(BuildContext context, Map<String, dynamic> alert) {
    // Validate required fields exist with reasonable defaults
    final alertType = alert['alert_type'];
    final message = alert['message'] ?? 'No message available';
    final timestamp = alert['timestamp'] ?? DateTime.now().toIso8601String();
    final source = alert['source'] ?? 'api';
    final isBluetoothSource = source == 'bluetooth';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(getAlertIcon(alertType), color: getAlertColor(alertType)),
                const SizedBox(width: 8),
                const Text('Alert'),
                if (isBluetoothSource)
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.bluetooth, color: Colors.blue, size: 16),
                  ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time: ${formatDateTime(timestamp)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isBluetoothSource)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Received via Bluetooth',
                      style: TextStyle(
                        color: Colors.blue,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
