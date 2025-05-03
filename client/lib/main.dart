import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vueling Connect',
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      themeMode: ThemeMode.dark, // Force dark mode
      home: const MyHomePage(title: 'Vueling Connect'),
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
  String _serverAddress =
      'localhost'; // Change to your computer's IP when testing on a real device
  String _serverPort = '8000';

  // Stored flight information
  List<Map<String, dynamic>> _savedFlights = [];

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _loadSavedFlights();
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

  Future<void> _saveFlights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedFlights', jsonEncode(_savedFlights));
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
        _savedFlights[index]['original_message_timestamp'],
      );
      final DateTime newTimestamp = DateTime.parse(
        newFlight['original_message_timestamp'],
      );

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
    if (flightNumber.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a flight number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _flightInfo = null;
      _errorMessage = '';
    });

    // Use 10.0.2.2 instead of localhost when running on Android emulator
    String host = _serverAddress;
    if (!kIsWeb && Platform.isAndroid) {
      // 10.0.2.2 is the special IP for host machine when using Android emulator
      host = '10.0.2.2';
    }

    final apiUrl = 'http://$host:$_serverPort/flight-status';
    print('Connecting to: $apiUrl');

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final List<dynamic> flightStatuses = jsonDecode(response.body);

        // Save all flight information
        for (var flight in flightStatuses) {
          _updateFlightInfo(Map<String, dynamic>.from(flight));
        }

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
        setState(() {
          _errorMessage = 'Failed to fetch flight info: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      // If we can't reach the server, try to show saved flight info
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
    }
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _flightNumberController.dispose();
    super.dispose();
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
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
            const SizedBox(height: 24),

            // Flight info display
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage.isNotEmpty)
              SelectableText(_errorMessage, style: TextStyle(color: Colors.red))
            else if (_flightInfo != null)
              Card(
                elevation: 4,
                margin: EdgeInsets.zero,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flight ${_flightInfo!['flight_number']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: ${_flightInfo!['flight_status']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: getStatusColor(_flightInfo!['flight_status']),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_flightInfo!['flight_message']),
                      const SizedBox(height: 8),
                      Text(
                        'Last Updated: ${_formatDateTime(_flightInfo!['original_message_timestamp'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
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
                              'Status: ${flight['flight_status']}\n'
                              'Last Updated: ${_formatDateTime(flight['original_message_timestamp'])}',
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
}
