import 'dart:typed_data';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE peripheral for raw data advertisement
class BlePeripheralService {
  final PeripheralManager _manager = PeripheralManager();
  final Logger _logger = Logger('BlePeripheralService');
  bool _isAdvertising = false;

  /// Whether the device is currently advertising
  bool get isAdvertising => _isAdvertising;

  /// Broadcasts custom bytes via BLE advertisement
  Future<void> broadcastMessage(Uint8List message) async {
    // Ensure we stop any existing advertisement first
    if (_isAdvertising) {
      await stopBroadcast();
    }

    // Check permissions on Android
    if (Platform.isAndroid) {
      bool hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        _logger.severe('Missing required Bluetooth permissions, cannot start advertising');
        throw Exception('Missing required Bluetooth permissions');
      }
    }

    try {
      // Configure advertisement with optimal settings for Android
      final adv = Advertisement(
        // Use a recognizable name for easier debugging
        name: 'VuelingConnect',
        // Include manufacturer data with our custom ID
        manufacturerSpecificData: [
          ManufacturerSpecificData(id: 0xFFFF, data: message),
        ],
      );

      _logger.info('Starting BLE advertising with data: ${message.length} bytes');
      await _manager.startAdvertising(adv);
      _isAdvertising = true;
      _logger.info('Started BLE advertising successfully');
    } catch (e) {
      _logger.severe('Error starting BLE advertising: $e');
      rethrow;
    }
  }

  /// Check and request Bluetooth permissions
  Future<bool> _checkAndRequestPermissions() async {
    _logger.info('Checking Bluetooth permissions');
    
    // Check if we have the necessary permissions
    bool hasBluetoothAdvertise = await Permission.bluetoothAdvertise.isGranted;
    bool hasBluetoothConnect = await Permission.bluetoothConnect.isGranted;

    // If any permission is missing, request all of them
    if (!hasBluetoothAdvertise || !hasBluetoothConnect) {
      _logger.info('Requesting Bluetooth permissions');
      
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      
      // Check if all permissions were granted
      return statuses[Permission.bluetoothAdvertise] == PermissionStatus.granted &&
             statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
    }
    
    return true;
  }

  /// Stops BLE advertising
  Future<void> stopBroadcast() async {
    try {
      await _manager.stopAdvertising();
      _isAdvertising = false;
      _logger.info('Stopped BLE advertising');
    } catch (e) {
      _logger.warning('Error stopping BLE advertising: $e');
    }
  }
}
