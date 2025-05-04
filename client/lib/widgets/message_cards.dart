import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../utils/string_utils.dart';
import '../utils/date_utils.dart';
import '../services/subscription_service.dart';

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

  // Helper method to get appropriate icon for flight status
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return Icons.schedule;
      case 'departed':
        return Icons.flight_takeoff;
      case 'arrived':
        return Icons.flight_land;
      case 'delayed':
        return Icons.update;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Validate required fields exist with reasonable defaults
    final flightNumber = flight['flight_number'] ?? 'Unknown';
    final flightStatus = flight['flight_status'] ?? 'unknown';
    final timestamp = flight['timestamp'] ?? DateTime.now().toIso8601String();
    final source = flight['source'] ?? 'api';
    final isBluetoothSource = source == 'bluetooth';
    final String? eta = flight['eta']; // ETA may not be available
    final String? destination =
        flight['destination']; // Destination may not be available

    // Get subscription service
    final subscriptionService = Provider.of<SubscriptionService>(context);
    final isSubscribed = subscriptionService.isSubscribed(flightNumber);

    final cardContent = Card(
      elevation: 4,
      margin: isExpanded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with flight number and bluetooth icon if applicable
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.flight,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Flight $flightNumber',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Add subscription indicator
                    if (isSubscribed)
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Icon(
                          Icons.notifications_active,
                          color: Colors.amber,
                          size: 16,
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (destination != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 18,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            destination,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),

            // Status with icon
            Row(
              children: [
                Icon(
                  _getStatusIcon(flightStatus),
                  color: getStatusColor(flightStatus),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  capitalizeFirstLetter(flightStatus),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: getStatusColor(flightStatus),
                  ),
                ),
              ],
            ),

            // ETA with icon if available and status appropriate
            if (eta != null &&
                flightStatus != 'arrived' &&
                flightStatus != 'cancelled') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ETA: ${formatDateTime(eta)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 6),
            // Last updated info and subscription button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.update, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      formatDateTime(timestamp),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Subscription button
                    IconButton(
                      icon: Icon(
                        isSubscribed ? Icons.notifications_off : Icons.notifications_none,
                        size: 20,
                        color: isSubscribed ? Colors.amber : Colors.white70,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: isSubscribed ? 'Unsubscribe' : 'Subscribe to updates',
                      onPressed: () {
                        if (isSubscribed) {
                          subscriptionService.unsubscribeFromFlight(flightNumber);
                        } else {
                          subscriptionService.subscribeToFlight(flightNumber);
                          // Show confirmation
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Subscribed to Flight $flightNumber updates', style: const TextStyle(color: Colors.white)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    // BLE indicator
                    // if (isBluetoothSource && !isExpanded)
                    //   const Text(
                    //     'BLE',
                    //     style: TextStyle(
                    //       color: Colors.blue,
                    //       fontWeight: FontWeight.bold,
                    //       fontSize: 12,
                    //     ),
                    //   ),
                  ],
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

    return GestureDetector(
      onTap: onTap ?? () => _showAlertDialog(context, alert),
      child: Card(
        elevation: 4,
        color: getAlertColor(alertType).withOpacity(0.2),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alert header
              Row(
                children: [
                  Icon(
                    getAlertIcon(alertType),
                    color: getAlertColor(alertType),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    capitalizeFirstLetter(alertType),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isBluetoothSource)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(
                        Icons.bluetooth,
                        color: Colors.blue,
                        size: 16,
                      ),
                    ),
                ],
              ),
              const Divider(height: 16),
              // Alert message
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(message, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 4),
              // Timestamp and source info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatDateTime(timestamp),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                    ],
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
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatDateTime(timestamp),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (isBluetoothSource)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.bluetooth, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'Received via Bluetooth',
                          style: TextStyle(
                            color: Colors.blue,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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
