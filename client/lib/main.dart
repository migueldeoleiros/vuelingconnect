import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vueling Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
      ),
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

  @override
  void initState() {
    super.initState();
    _initBluetooth();
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
        final flightInfo = flightStatuses.firstWhere(
          (flight) => flight['flight_number'] == flightNumber,
          orElse: () => null,
        );

        setState(() {
          _flightInfo = flightInfo;
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
      setState(() {
        _errorMessage = 'Error: $e';
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
        backgroundColor: Colors.yellow,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showServerSettings,
            tooltip: 'Server Settings',
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
                      border: OutlineInputBorder(),
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
                          color: _getStatusColor(_flightInfo!['flight_status']),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Scheduled':
        return Colors.blue;
      case 'Departed':
        return Colors.green;
      case 'Arrived':
        return Colors.purple;
      case 'Delayed':
        return Colors.orange;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
}
