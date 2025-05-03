import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_central_service.dart';
import '../services/ble_peripheral_service.dart';
import '../ble_message.dart';
import '../utils/string_utils.dart';
import '../utils/date_utils.dart';
import '../widgets/message_cards.dart';
import '../theme.dart';
import '../providers/bluetooth_state_provider.dart';

class BluetoothView extends StatefulWidget {
  final List<Map<String, dynamic>> savedFlights;
  final Function(bool) onSourceDeviceToggled;

  const BluetoothView({
    super.key,
    required this.savedFlights,
    required this.onSourceDeviceToggled,
  });

  @override
  _BluetoothViewState createState() => _BluetoothViewState();
}

class _BluetoothViewState extends State<BluetoothView> {
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

    // Check permissions before initializing Bluetooth
    if (Platform.isAndroid) {
      _checkAndRequestPermissions();
    }

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

  // Toggle source device mode
  void _toggleSourceDevice(bool value) {
    final provider = Provider.of<BluetoothStateProvider>(
      context,
      listen: false,
    );
    provider.setSourceDevice(value);

    // Notify the parent component about the change
    widget.onSourceDeviceToggled(value);
  }

  // Check and request Bluetooth permissions
  Future<void> _checkAndRequestPermissions() async {
    // Check if we have the necessary permissions
    bool hasBluetoothScan = await Permission.bluetoothScan.isGranted;
    bool hasBluetoothConnect = await Permission.bluetoothConnect.isGranted;
    bool hasBluetoothAdvertise = await Permission.bluetoothAdvertise.isGranted;
    bool hasLocation = await Permission.location.isGranted;

    // If any permission is missing, request all of them
    if (!hasBluetoothScan ||
        !hasBluetoothConnect ||
        !hasBluetoothAdvertise ||
        !hasLocation) {
      print('Requesting Bluetooth permissions from Bluetooth view...');

      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.bluetooth,
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.bluetoothAdvertise,
            Permission.location,
          ].request();

      // Log the results
      statuses.forEach((permission, status) {
        print('$permission: $status');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothProvider = Provider.of<BluetoothStateProvider>(context);

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
            value: bluetoothProvider.isSourceDevice,
            onChanged: _toggleSourceDevice,
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    if (bluetoothProvider.isScanning) {
                      await _centralService.stopDiscovery();
                      bluetoothProvider.setScanning(false);
                    } else {
                      await _centralService.startDiscovery();
                      bluetoothProvider.setScanning(true);
                    }
                  },
                  child: Text(
                    bluetoothProvider.isScanning ? 'Stop Scan' : 'Start Scan',
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (bluetoothProvider.isAdvertising) {
                      await _peripheralService.stopBroadcast();
                      bluetoothProvider.setAdvertising(false);
                      setState(() {
                        _currentBroadcastMessage = null;
                      });
                    } else {
                      // Select what to broadcast
                      _showBroadcastOptionsDialog();
                    }
                  },
                  child: Text(
                    bluetoothProvider.isAdvertising
                        ? 'Stop Broadcast'
                        : 'Start Broadcast',
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
                Text(
                  'Scanning: ${bluetoothProvider.isScanning ? "Active" : "Inactive"}',
                ),
                Text(
                  'Broadcasting: ${bluetoothProvider.isAdvertising ? "Active" : "Inactive"}',
                ),
                Text(
                  'Role: ${bluetoothProvider.isSourceDevice ? "Source" : "Relay"}',
                ),
                Text('Received Messages: ${_receivedMessages.length}'),
              ],
            ),
          ),

          // Current broadcast message
          if (bluetoothProvider.isAdvertising &&
              _currentBroadcastMessage != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    'Currently Broadcasting:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child:
                      _currentBroadcastMessage!.msgType == MsgType.flightStatus
                          ? FlightCard(
                            flight: {
                              'flight_number':
                                  _currentBroadcastMessage!.flightNumber,
                              'flight_status':
                                  _currentBroadcastMessage!.status
                                      .toString()
                                      .split('.')
                                      .last,
                              'flight_message':
                                  'This flight information is being broadcast',
                              'timestamp':
                                  DateTime.fromMillisecondsSinceEpoch(
                                    _currentBroadcastMessage!.timestamp * 1000,
                                  ).toIso8601String(),
                            },
                            isExpanded: true,
                          )
                          : AlertCard(
                            alert: {
                              'alert_type':
                                  _currentBroadcastMessage!.alertMessage
                                      .toString()
                                      .split('.')
                                      .last,
                              'message': 'This alert is being broadcast',
                              'timestamp':
                                  DateTime.fromMillisecondsSinceEpoch(
                                    _currentBroadcastMessage!.timestamp * 1000,
                                  ).toIso8601String(),
                            },
                          ),
                ),
              ],
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
                        if (message.msgType == MsgType.flightStatus) {
                          return FlightCard(
                            flight: {
                              'flight_number': message.flightNumber,
                              'flight_status':
                                  message.status.toString().split('.').last,
                              'flight_message': 'Received flight update',
                              'timestamp':
                                  DateTime.fromMillisecondsSinceEpoch(
                                    message.timestamp * 1000,
                                  ).toIso8601String(),
                            },
                          );
                        } else {
                          return AlertCard(
                            alert: {
                              'alert_type':
                                  message.alertMessage
                                      .toString()
                                      .split('.')
                                      .last,
                              'message': 'Alert received via Bluetooth',
                              'timestamp':
                                  DateTime.fromMillisecondsSinceEpoch(
                                    message.timestamp * 1000,
                                  ).toIso8601String(),
                            },
                          );
                        }
                      },
                    ),
          ),
        ],
      ),
    );
  }

  void _showBroadcastOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Broadcast Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flight),
                title: const Text('Flight Status'),
                onTap: () {
                  Navigator.pop(context);
                  _showFlightSelectionDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.warning),
                title: const Text('Alert'),
                onTap: () {
                  Navigator.pop(context);
                  _showAlertSelectionDialog();
                },
              ),
            ],
          ),
        );
      },
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Flight to Broadcast'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.savedFlights.length,
              itemBuilder: (context, index) {
                final flight = widget.savedFlights[index];
                return ListTile(
                  title: Text('Flight ${flight['flight_number']}'),
                  subtitle: Text(
                    '${flight['flight_status']} - ${formatDateTime(flight['timestamp'])}',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    // Create BLE message from flight
                    // Important: Preserve the original timestamp
                    final timestamp =
                        DateTime.parse(
                          flight['timestamp'],
                        ).millisecondsSinceEpoch ~/
                        1000;

                    final msg = BleMessage.flightStatus(
                      flightNumber: flight['flight_number'],
                      status: _getFlightStatusEnum(flight['flight_status']),
                      timestamp: timestamp, // Use the original timestamp
                    );

                    setState(() {
                      _currentBroadcastMessage = msg;
                    });

                    await _peripheralService.broadcastMessage(msg.encode());
                    Provider.of<BluetoothStateProvider>(
                      context,
                      listen: false,
                    ).setAdvertising(true);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showAlertSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Alert Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var alertType in AlertMessage.values)
                ListTile(
                  leading: Icon(
                    getAlertIcon(alertType.toString().split('.').last),
                    color: getAlertColor(alertType.toString().split('.').last),
                  ),
                  title: Text(
                    capitalizeFirstLetter(alertType.toString().split('.').last),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    // Create BLE message with current timestamp
                    final msg = BleMessage.alert(
                      alertMessage: alertType,
                      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    );

                    setState(() {
                      _currentBroadcastMessage = msg;
                    });

                    await _peripheralService.broadcastMessage(msg.encode());
                    Provider.of<BluetoothStateProvider>(
                      context,
                      listen: false,
                    ).setAdvertising(true);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  FlightStatus _getFlightStatusEnum(String? status) {
    if (status == null) return FlightStatus.scheduled;

    switch (status.toLowerCase()) {
      case 'departed':
        return FlightStatus.departed;
      case 'arrived':
        return FlightStatus.arrived;
      case 'delayed':
        return FlightStatus.delayed;
      case 'cancelled':
        return FlightStatus.cancelled;
      case 'scheduled':
      default:
        return FlightStatus.scheduled;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
