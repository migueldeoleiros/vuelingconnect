import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import '../services/ble_central_service.dart';
import '../services/ble_peripheral_service.dart';
import '../ble_message.dart';
import '../utils/string_utils.dart';

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

  final List<BleMessage> _receivedMessages = [];
  BleMessage? _currentBroadcastMessage;

  @override
  void initState() {
    super.initState();
    _centralService = Provider.of<BleCentralService>(context, listen: false);
    _peripheralService = Provider.of<BlePeripheralService>(
      context,
      listen: false,
    );

    // Listen to BLE message stream
    _centralService.dataStream.listen((data) {
      try {
        final msg = BleMessage.decode(Uint8List.fromList(data));
        setState(() {
          _receivedMessages.add(msg);
        });
      } catch (e) {
        print('Error decoding BLE message: $e');
      }
    });
  }

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
                      await _centralService.stopDiscovery();
                    } else {
                      await _centralService.startDiscovery();
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
                      await _peripheralService.stopBroadcast();
                      setState(() {
                        _isAdvertising = false;
                        _currentBroadcastMessage = null;
                      });
                    } else {
                      // Select what to broadcast
                      _showBroadcastOptionsDialog();
                    }
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
                Text('Received Messages: ${_receivedMessages.length}'),
              ],
            ),
          ),

          // Current broadcast message
          if (_isAdvertising && _currentBroadcastMessage != null)
            Card(
              margin: const EdgeInsets.all(16.0),
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getMessageIcon(_currentBroadcastMessage!),
                          color: _getMessageColor(_currentBroadcastMessage!),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Currently Broadcasting:',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getMessageTitle(_currentBroadcastMessage!),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(_getMessageDetails(_currentBroadcastMessage!)),
                  ],
                ),
              ),
            ),

          // Received messages list
          Expanded(
            child:
                _receivedMessages.isEmpty
                    ? const Center(child: Text('No messages received'))
                    : ListView.builder(
                      itemCount: _receivedMessages.length,
                      itemBuilder: (context, index) {
                        final message = _receivedMessages[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: ListTile(
                            title: Text(_getMessageTitle(message)),
                            subtitle: Text(_getMessageDetails(message)),
                            leading: Icon(
                              _getMessageIcon(message),
                              color: _getMessageColor(message),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // Helper methods for message display
  String _getMessageTitle(BleMessage message) {
    if (message.msgType == MsgType.flightStatus) {
      return 'Flight ${message.flightNumber}';
    } else {
      return 'Alert: ${_getAlertName(message.alertMessage!)}';
    }
  }

  String _getMessageDetails(BleMessage message) {
    if (message.msgType == MsgType.flightStatus) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        message.timestamp * 1000,
      );
      final statusText = capitalizeFirstLetter(
        message.status.toString().split('.').last,
      );
      return 'Status: $statusText\nTime: ${dateTime.hour}:${dateTime.minute}';
    } else {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        message.timestamp * 1000,
      );
      return 'Time: ${dateTime.hour}:${dateTime.minute}';
    }
  }

  IconData _getMessageIcon(BleMessage message) {
    if (message.msgType == MsgType.flightStatus) {
      return Icons.flight;
    } else {
      switch (message.alertMessage) {
        case AlertMessage.medical:
          return Icons.medical_services;
        case AlertMessage.evacuation:
          return Icons.exit_to_app;
        case AlertMessage.fire:
          return Icons.local_fire_department;
        case AlertMessage.aliens:
          return Icons.warning;
        default:
          return Icons.notification_important;
      }
    }
  }

  Color _getMessageColor(BleMessage message) {
    if (message.msgType == MsgType.flightStatus) {
      switch (message.status) {
        case FlightStatus.scheduled:
          return Colors.blue;
        case FlightStatus.departed:
          return Colors.green;
        case FlightStatus.arrived:
          return Colors.purple;
        case FlightStatus.delayed:
          return Colors.orange;
        case FlightStatus.cancelled:
          return Colors.red;
        default:
          return Colors.grey;
      }
    } else {
      switch (message.alertMessage) {
        case AlertMessage.medical:
          return Colors.blue;
        case AlertMessage.evacuation:
          return Colors.red;
        case AlertMessage.fire:
          return Colors.orange;
        case AlertMessage.aliens:
          return Colors.purple;
        default:
          return Colors.grey;
      }
    }
  }

  String _getAlertName(AlertMessage alert) {
    return capitalizeFirstLetter(alert.toString().split('.').last);
  }

  void _showBroadcastOptionsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Broadcast Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Flight Status'),
                  leading: const Icon(Icons.flight),
                  onTap: () {
                    Navigator.pop(context);
                    _showFlightSelectionDialog();
                  },
                ),
                const Divider(),
                ListTile(
                  title: const Text('Alert Message'),
                  leading: const Icon(Icons.warning),
                  onTap: () {
                    Navigator.pop(context);
                    _showAlertSelectionDialog();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  void _showFlightSelectionDialog() {
    if (widget.savedFlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No flights available to broadcast')),
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Flight'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: widget.savedFlights.length,
                itemBuilder: (context, index) {
                  final flight = widget.savedFlights[index];
                  return ListTile(
                    title: Text('Flight ${flight['flight_number']}'),
                    subtitle: Text('Status: ${flight['flight_status']}'),
                    onTap: () {
                      Navigator.pop(context);
                      _broadcastFlightStatus(flight);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  void _showAlertSelectionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Alert Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Medical Emergency'),
                  leading: const Icon(
                    Icons.medical_services,
                    color: Colors.blue,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _broadcastAlert(AlertMessage.medical);
                  },
                ),
                ListTile(
                  title: const Text('Evacuation'),
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  onTap: () {
                    Navigator.pop(context);
                    _broadcastAlert(AlertMessage.evacuation);
                  },
                ),
                ListTile(
                  title: const Text('Fire'),
                  leading: const Icon(
                    Icons.local_fire_department,
                    color: Colors.orange,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _broadcastAlert(AlertMessage.fire);
                  },
                ),
                ListTile(
                  title: const Text('Other Alert'),
                  leading: const Icon(Icons.warning, color: Colors.purple),
                  onTap: () {
                    Navigator.pop(context);
                    _broadcastAlert(AlertMessage.aliens);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Future<void> _broadcastFlightStatus(Map<String, dynamic> flight) async {
    final flightNumber = flight['flight_number'];
    final statusStr = flight['flight_status'].toLowerCase();

    // Convert string status to enum
    FlightStatus? status;
    for (var s in FlightStatus.values) {
      if (s.toString().split('.').last == statusStr) {
        status = s;
        break;
      }
    }

    if (status == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid flight status')));
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bleMessage = BleMessage.flightStatus(
      flightNumber: flightNumber,
      status: status,
      timestamp: now,
    );

    await _peripheralService.broadcastMessage(bleMessage.encode());
    setState(() {
      _isAdvertising = true;
      _currentBroadcastMessage = bleMessage;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Broadcasting flight $flightNumber status')),
    );
  }

  Future<void> _broadcastAlert(AlertMessage alertType) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bleMessage = BleMessage.alert(
      alertMessage: alertType,
      timestamp: now,
    );

    await _peripheralService.broadcastMessage(bleMessage.encode());
    setState(() {
      _isAdvertising = true;
      _currentBroadcastMessage = bleMessage;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Broadcasting ${_getAlertName(alertType)} alert'),
        backgroundColor:
            alertType == AlertMessage.evacuation ||
                    alertType == AlertMessage.fire
                ? Colors.red
                : null,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
