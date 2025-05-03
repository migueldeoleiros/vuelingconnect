import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_central_service.dart';
import '../services/ble_peripheral_service.dart';
import '../models/flight_info.dart';
import '../theme.dart';

class BluetoothView extends StatefulWidget {
  final List<Map<String, dynamic>> savedFlights;

  const BluetoothView({super.key, required this.savedFlights});

  @override
  _BluetoothViewState createState() => _BluetoothViewState();
}

class _BluetoothViewState extends State<BluetoothView> {
  bool _isSourceDevice = false;
  bool _isScanning = false;
  bool _isAdvertising = false;

  late final BleCentralService _centralService;
  late final BlePeripheralService _peripheralService;

  List<FlightInfo> _flightList = [];

  @override
  void initState() {
    super.initState();
    _centralService = Provider.of<BleCentralService>(context, listen: false);
    _peripheralService = Provider.of<BlePeripheralService>(
      context,
      listen: false,
    );

    // Listen to flight updates from central service
    _centralService.flightsStream.listen((flights) {
      setState(() {
        _flightList = flights;

        // If we're acting as a mesh node, also rebroadcast the data
        if (!_isSourceDevice && _isAdvertising) {
          _peripheralService.updateFlights(_flightList);
        }
      });
    });

    // Convert saved flights to FlightInfo objects
    _convertSavedFlights();
  }

  void _convertSavedFlights() {
    final flightInfoList =
        widget.savedFlights.map((flightMap) {
          // Convert from flight_number format to flightNumber format for consistency
          return FlightInfo(
            flightNumber: flightMap['flight_number'] ?? '',
            destination: flightMap['destination'] ?? 'Unknown',
            gate: flightMap['gate'] ?? 'TBD',
            // Handle non-existent fields by providing defaults
            departureTime:
                DateTime.tryParse(flightMap['departure_time'] ?? '') ??
                DateTime.now().add(const Duration(hours: 1)),
            status: flightMap['flight_status'] ?? 'Unknown',
            timestamp:
                DateTime.tryParse(
                  flightMap['original_message_timestamp'] ?? '',
                ) ??
                DateTime.now(),
          );
        }).toList();

    _flightList = flightInfoList;

    // If we're the source device, start advertising immediately
    if (_isSourceDevice && _flightList.isNotEmpty) {
      _peripheralService.startAdvertising(_flightList);
      setState(() {
        _isAdvertising = true;
      });
    }
  }

  // Using the getStatusColor from theme.dart

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Mesh Network')),
      body: Column(
        children: [
          // Source device switch
          SwitchListTile(
            title: const Text('Source Device'),
            subtitle: const Text(
              'Enable to act as the original source of flight information',
            ),
            value: _isSourceDevice,
            onChanged: (value) {
              setState(() {
                _isSourceDevice = value;
              });
            },
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    if (_isScanning) {
                      await _centralService.stopScan();
                    } else {
                      await _centralService.startScan();
                    }
                    setState(() {
                      _isScanning = !_isScanning;
                    });
                  },
                  child: Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_isAdvertising) {
                      await _peripheralService.stopAdvertising();
                    } else {
                      await _peripheralService.startAdvertising(_flightList);
                    }
                    setState(() {
                      _isAdvertising = !_isAdvertising;
                    });
                  },
                  child: Text(
                    _isAdvertising ? 'Stop Broadcast' : 'Start Broadcast',
                  ),
                ),
              ],
            ),
          ),

          // Connection status
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Scanning: ${_isScanning ? "Active" : "Inactive"}'),
                Text('Broadcasting: ${_isAdvertising ? "Active" : "Inactive"}'),
                Text('Role: ${_isSourceDevice ? "Source" : "Relay"}'),
                Text('Flights in memory: ${_flightList.length}'),
              ],
            ),
          ),

          // Flight list
          Expanded(
            child:
                _flightList.isEmpty
                    ? const Center(
                      child: Text('No flight information available'),
                    )
                    : ListView.builder(
                      itemCount: _flightList.length,
                      itemBuilder: (context, index) {
                        final flight = _flightList[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: ListTile(
                            title: Text('Flight ${flight.flightNumber}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status: ${flight.status}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: getStatusColor(flight.status),
                                  ),
                                ),
                                Text('Destination: ${flight.destination}'),
                                Text('Gate: ${flight.gate}'),
                                Text(
                                  'Departure: ${flight.departureTime.hour}:${flight.departureTime.minute.toString().padLeft(2, '0')}',
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _centralService.dispose();
    super.dispose();
  }
}
