import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../services/ble_central_service.dart';
import '../services/ble_peripheral_service.dart';

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

  final List<String> _receivedMessages = [];

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
      final msg = utf8.decode(data);
      setState(() {
        _receivedMessages.add(msg);
      });
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
                    } else {
                      // Broadcast sample message
                      final bytes = Uint8List.fromList(
                        utf8.encode('Hello BLE'),
                      );
                      await _peripheralService.broadcastMessage(bytes);
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
                Text('Received Messages: ${_receivedMessages.length}'),
              ],
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
                            title: Text('Message $index'),
                            subtitle: Text(message),
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
