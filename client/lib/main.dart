import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:prueba_app/ble_message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'views/bluetooth_view.dart';
import 'services/ble_central_service.dart';
import 'services/ble_peripheral_service.dart';

void main() {
  // Set up logging
  // testBleMessage();
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('Error: ${record.error}\nStack trace: ${record.stackTrace}');
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<BleCentralService>(
          create: (_) => BleCentralService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<BlePeripheralService>(create: (_) => BlePeripheralService()),
      ],
      child: MaterialApp(
        title: 'Vueling Connect',
        theme: getLightTheme(),
        darkTheme: getDarkTheme(),
        themeMode: ThemeMode.dark, // Force dark mode
        home: const MyHomePage(title: 'Vueling Connect'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Flight tracking
  final TextEditingController _flightNumberController = TextEditingController();
  Map<String, dynamic>? _flightInfo;
  bool _isLoading = false;
  String _errorMessage = '';
  String _serverAddress = 'localhost';
  String _serverPort = '8000';

  // Stored flight information
  List<Map<String, dynamic>> _savedFlights = [];

  // Alerts information
  final List<Map<String, dynamic>> _activeAlerts = [];

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _loadSavedFlights();
    _loadServerSettings();
  }

  Future<void> _loadSavedFlights() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFlightsJson = prefs.getString('savedFlights');

    if (savedFlightsJson != null) {
      setState(() {
        _savedFlights = List<Map<String, dynamic>>.from(
          (jsonDecode(savedFlightsJson) as List).map(
            (flight) => Map<String, dynamic>.from(flight as Map),
          ),
        );
      });
    }
  }

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverAddress = prefs.getString('serverAddress') ?? 'localhost';
      _serverPort = prefs.getString('serverPort') ?? '8000';
    });
  }

  Future<void> _saveFlights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedFlights', jsonEncode(_savedFlights));
  }

  Future<void> _saveServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', _serverAddress);
    await prefs.setString('serverPort', _serverPort);
  }

  // Update existing flight or add new one if it doesn't exist
  void _updateFlightInfo(Map<String, dynamic> newFlight) {
    final flightNumber = newFlight['flight_number'];
    final index = _savedFlights.indexWhere(
      (flight) => flight['flight_number'] == flightNumber,
    );

    if (index != -1) {
      // Flight exists, check timestamp
      final DateTime existingTimestamp = DateTime.parse(
        _savedFlights[index]['timestamp'],
      );
      final DateTime newTimestamp = DateTime.parse(newFlight['timestamp']);

      if (newTimestamp.isAfter(existingTimestamp)) {
        setState(() {
          _savedFlights[index] = newFlight;
          _flightInfo = newFlight;
        });
      } else {
        // Use existing flight info if it's newer
        setState(() {
          _flightInfo = _savedFlights[index];
        });
      }
    } else {
      // New flight, add it
      setState(() {
        _savedFlights.add(newFlight);
        _flightInfo = newFlight;
      });
    }

    _saveFlights();
  }

  // Save an alert
  void _addAlert(Map<String, dynamic> alert) {
    setState(() {
      _activeAlerts.add(alert);
    });
  }

  Future<void> _initBluetooth() async {
    // Habilita logs
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);

    // Verifica soporte de Bluetooth
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      return;
    }

    // Escucha cambios en el estado del adaptador
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
      BluetoothAdapterState state,
    ) {
      print('Bluetooth state: $state');
      if (state == BluetoothAdapterState.on) {
        // Aquí podrías iniciar el escaneo, etc.
        _playSound('a.mp3');
        print("Bluetooth está activado");
      } else {
        _playSound('b.mp3');
        print("Bluetooth desactivado o sin permisos");
      }
    });

    // En Android, intenta activar Bluetooth automáticamente
    if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  Future<void> _playSound(String path) async {
    try {
      await _audioPlayer.play(AssetSource(path));
    } catch (e) {
      print("Error al reproducir sonido: $e");
    }
  }

  Future<void> _fetchFlightInfo() async {
    final flightNumber = _flightNumberController.text.trim();

    setState(() {
      _isLoading = true;
      _flightInfo = null;
      _errorMessage = '';
    });

    // Use 10.0.2.2 instead of localhost when running on Android emulator
    String host = _serverAddress;
    if (!kIsWeb && Platform.isAndroid && host == 'localhost') {
      // 10.0.2.2 is the special IP for host machine when using Android emulator
      host = '10.0.2.2';
    }

    final apiUrl = 'http://$host:$_serverPort/flight-status';
    print('Connecting to: $apiUrl');

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final List<dynamic> messages = jsonDecode(response.body);

        // Process messages by type
        for (var msg in messages) {
          String msgType = msg['msg_type'];

          if (msgType == 'flightStatus' &&
              msg['flight_number'] != null &&
              msg['status'] != null) {
            // Convert to our format
            final flight = {
              'flight_number': msg['flight_number'],
              'flight_status': msg['status'],
              'timestamp':
                  DateTime.fromMillisecondsSinceEpoch(
                    msg['timestamp'] * 1000,
                  ).toIso8601String(),
              'flight_message': _getFlightStatusMessage(msg['status']),
            };
            _updateFlightInfo(flight);
          } else if (msgType == 'alert' && msg['alert_type'] != null) {
            // Process alert
            final alert = {
              'alert_type': msg['alert_type'],
              'timestamp':
                  DateTime.fromMillisecondsSinceEpoch(
                    msg['timestamp'] * 1000,
                  ).toIso8601String(),
              'message': _getAlertMessage(msg['alert_type']),
            };
            _addAlert(alert);
          }
        }

        // If a flight number was specified, find that specific flight
        if (flightNumber.isNotEmpty) {
          // Find the requested flight
          final matchingFlight = _savedFlights.firstWhere(
            (flight) => flight['flight_number'] == flightNumber,
            orElse: () => <String, dynamic>{},
          );

          setState(() {
            _flightInfo = matchingFlight.isEmpty ? null : matchingFlight;
            if (_flightInfo == null) {
              _errorMessage = 'Flight not found';
            }
            _isLoading = false;
          });
        } else {
          // No flight number specified, just show all flights
          setState(() {
            _flightInfo = null;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to fetch flight info: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      // If we can't reach the server, try to show saved flight info if a flight number was specified
      if (flightNumber.isNotEmpty) {
        final savedFlight = _savedFlights.firstWhere(
          (flight) => flight['flight_number'] == flightNumber,
          orElse: () => <String, dynamic>{},
        );

        setState(() {
          if (savedFlight.isNotEmpty) {
            _flightInfo = savedFlight;
            _errorMessage = 'Using saved data. Server error: $e';
          } else {
            _errorMessage = 'Error: $e';
          }
          _isLoading = false;
        });
      } else {
        // Just show saved flights if we can't reach the server
        setState(() {
          _errorMessage = 'Using saved data. Server error: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Helper to get flight status message
  String _getFlightStatusMessage(String status) {
    switch (status) {
      case 'scheduled':
        return 'Your flight is scheduled to depart as planned.';
      case 'departed':
        return 'Your flight has departed.';
      case 'arrived':
        return 'Your flight has arrived at the destination.';
      case 'delayed':
        return 'Your flight is delayed. Please check the departure board.';
      case 'cancelled':
        return 'Your flight has been cancelled. Please contact Vueling staff.';
      default:
        return 'Flight status unknown.';
    }
  }

  // Helper to get alert message
  String _getAlertMessage(String alertType) {
    switch (alertType) {
      case 'medical':
        return 'Medical emergency alert. If you are a doctor or medical professional, please identify yourself to cabin crew.';
      case 'evacuation':
        return 'EMERGENCY! Please prepare for evacuation and follow crew instructions immediately!';
      case 'fire':
        return 'EMERGENCY! Fire alert. Please remain calm and follow crew instructions.';
      case 'aliens':
        return 'ALERT: Unexpected visitors detected. This is not a drill.';
      default:
        return 'Unknown alert.';
    }
  }

  // Get color for alert type
  Color _getAlertColor(String alertType) {
    switch (alertType) {
      case 'medical':
        return Colors.blue;
      case 'evacuation':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'aliens':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // Show alert details dialog
  void _showAlertDialog(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  _getAlertIcon(alert['alert_type']),
                  color: _getAlertColor(alert['alert_type']),
                ),
                const SizedBox(width: 8),
                const Text('Alert'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['message'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time: ${_formatDateTime(alert['timestamp'])}',
                  style: Theme.of(context).textTheme.bodySmall,
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

  // Get icon for alert type
  IconData _getAlertIcon(String alertType) {
    switch (alertType) {
      case 'medical':
        return Icons.medical_services;
      case 'evacuation':
        return Icons.exit_to_app;
      case 'fire':
        return Icons.local_fire_department;
      case 'aliens':
        return Icons.warning;
      default:
        return Icons.notification_important;
    }
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _flightNumberController.dispose();
    super.dispose();
  }

  // Flight card widget for reuse
  Widget _buildFlightCard(
    Map<String, dynamic> flight, {
    bool isExpanded = false,
  }) {
    final cardContent = Card(
      elevation: 4,
      margin: isExpanded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flight ${flight['flight_number']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${_capitalizeFirstLetter(flight['flight_status'])}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: getStatusColor(flight['flight_status']),
              ),
            ),
            const SizedBox(height: 8),
            Text(flight['flight_message']),
            const SizedBox(height: 8),
            Text(
              'Last Updated: ${_formatDateTime(flight['timestamp'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );

    if (isExpanded) {
      return SizedBox(width: double.infinity, child: cardContent);
    }

    return cardContent;
  }

  // Alert card widget
  Widget _buildAlertCard(Map<String, dynamic> alert) {
    return Card(
      elevation: 4,
      color: _getAlertColor(alert['alert_type']).withOpacity(0.2),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          _getAlertIcon(alert['alert_type']),
          color: _getAlertColor(alert['alert_type']),
        ),
        title: Text(
          _capitalizeFirstLetter(alert['alert_type']),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(alert['message']),
        trailing: Text(
          _formatDateTime(alert['timestamp']).split(' ')[1], // Just show time
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => _showAlertDialog(alert),
      ),
    );
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.black,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showServerSettings,
            tooltip: 'Server Settings',
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showSavedFlights,
            tooltip: 'Saved Flights',
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth),
            onPressed: _navigateToBluetoothView,
            tooltip: 'Bluetooth Mesh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Alert section if there are active alerts
            if (_activeAlerts.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => _showAlertsDialog(),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildAlertCard(_activeAlerts.last),
              const SizedBox(height: 16),
            ],

            // Flight tracker section
            Text(
              'Flight Tracker',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _flightNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Flight Number (e.g., VY2375)',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _fetchFlightInfo,
                  child: const Text('Check Status'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  _flightNumberController.clear();
                  _fetchFlightInfo();
                },
                icon: const Icon(Icons.list),
                label: const Text('View All Flights'),
              ),
            ),
            const SizedBox(height: 16),

            // Flight info display
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage.isNotEmpty)
              SelectableText(_errorMessage, style: TextStyle(color: Colors.red))
            else if (_flightInfo != null)
              _buildFlightCard(_flightInfo!, isExpanded: true)
            else if (_savedFlights.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Flights',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _savedFlights.length,
                        itemBuilder: (context, index) {
                          final flight = _savedFlights[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _flightNumberController.text =
                                    flight['flight_number'];
                                _flightInfo = flight;
                              });
                            },
                            child: _buildFlightCard(flight),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Text(
                  'No flights available. Try connecting to the server or checking a specific flight.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
    } catch (e) {
      return isoString;
    }
  }

  void _showAlertsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Active Alerts'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child:
                  _activeAlerts.isEmpty
                      ? const Center(child: Text('No active alerts'))
                      : ListView.builder(
                        itemCount: _activeAlerts.length,
                        itemBuilder: (context, index) {
                          return _buildAlertCard(_activeAlerts[index]);
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (_activeAlerts.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _activeAlerts.clear();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
            ],
          ),
    );
  }

  void _showServerSettings() {
    final addressController = TextEditingController(text: _serverAddress);
    final portController = TextEditingController(text: _serverPort);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Server Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Server Address',
                    hintText: 'localhost or IP address',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    labelText: 'Server Port',
                    hintText: '8000',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _serverAddress = addressController.text;
                    _serverPort = portController.text;
                  });
                  // Save to shared preferences
                  _saveServerSettings();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Server set to: $_serverAddress:$_serverPort',
                      ),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  void _showSavedFlights() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Saved Flights'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  _savedFlights.isEmpty
                      ? const Text('No saved flights')
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _savedFlights.length,
                        itemBuilder: (context, index) {
                          final flight = _savedFlights[index];
                          return ListTile(
                            title: Text('Flight ${flight['flight_number']}'),
                            subtitle: Text(
                              'Status: ${_capitalizeFirstLetter(flight['flight_status'])}\n'
                              'Last Updated: ${_formatDateTime(flight['timestamp'])}',
                            ),
                            onTap: () {
                              _flightNumberController.text =
                                  flight['flight_number'];
                              setState(() {
                                _flightInfo = flight;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
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

  void _navigateToBluetoothView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothView(savedFlights: _savedFlights),
      ),
    );
  }
}
