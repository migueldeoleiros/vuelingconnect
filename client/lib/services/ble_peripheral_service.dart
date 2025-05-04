import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE peripheral for raw data advertisement
class BlePeripheralService {
  final PeripheralManager _manager = PeripheralManager();
  final Logger _logger = Logger('BlePeripheralService');
  bool _isAdvertising = false;
  
  // Retry mechanism for broadcast failures
  Timer? _broadcastRetryTimer;
  static const int _broadcastRetryIntervalMs = 3000; // 3 seconds between retries
  static const int _maxBroadcastRetries = 3;
  int _broadcastRetryCount = 0;
  
  // Keep track of the last broadcast message for retries
  Uint8List? _lastBroadcastMessage;

  /// Whether the device is currently advertising
  bool get isAdvertising => _isAdvertising;

  /// Broadcasts custom bytes via BLE advertisement
  Future<void> broadcastMessage(Uint8List message) async {
    // Store the message for potential retries
    _lastBroadcastMessage = message;
    
    // Reset retry count
    _broadcastRetryCount = 0;
    
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
      
      // For Android, set up a refresh timer to restart advertising periodically
      // This helps with visibility issues on some Android devices
      if (Platform.isAndroid) {
        _setupAdvertisingRefresh();
      }
    } catch (e) {
      _logger.severe('Error starting BLE advertising: $e');
      _retryBroadcastIfNeeded();
      rethrow;
    }
  }
  
  /// Set up periodic advertising refresh for Android
  void _setupAdvertisingRefresh() {
    // Cancel any existing timer
    _broadcastRetryTimer?.cancel();
    
    // Restart advertising every 15 seconds to improve visibility
    _broadcastRetryTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_isAdvertising && _lastBroadcastMessage != null) {
        _logger.info('Refreshing BLE advertisement to improve visibility');
        try {
          await stopBroadcast();
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Configure advertisement with optimal settings for Android
          final adv = Advertisement(
            // Use a recognizable name for easier debugging
            name: 'VuelingConnect',
            // Include manufacturer data with our custom ID
            manufacturerSpecificData: [
              ManufacturerSpecificData(id: 0xFFFF, data: _lastBroadcastMessage!),
            ],
          );
          
          await _manager.startAdvertising(adv);
          _isAdvertising = true;
        } catch (e) {
          _logger.warning('Error during advertising refresh: $e');
          _retryBroadcastIfNeeded();
        }
      }
    });
  }
  
  /// Retry broadcasting if needed after an error
  void _retryBroadcastIfNeeded() {
    if (_broadcastRetryCount < _maxBroadcastRetries && _lastBroadcastMessage != null) {
      _broadcastRetryCount++;
      _logger.info('Attempting to restart broadcasting (retry $_broadcastRetryCount of $_maxBroadcastRetries)');
      
      // Cancel any existing timer
      _broadcastRetryTimer?.cancel();
      
      // Try to restart after a delay
      _broadcastRetryTimer = Timer(Duration(milliseconds: _broadcastRetryIntervalMs), () async {
        try {
          // Make sure we're stopped first
          await stopBroadcast();
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Configure advertisement with optimal settings for Android
          final adv = Advertisement(
            // Use a recognizable name for easier debugging
            name: 'VuelingConnect',
            // Include manufacturer data with our custom ID
            manufacturerSpecificData: [
              ManufacturerSpecificData(id: 0xFFFF, data: _lastBroadcastMessage!),
            ],
          );
          
          await _manager.startAdvertising(adv);
          _isAdvertising = true;
          _logger.info('Successfully restarted BLE advertising');
        } catch (e) {
          _logger.severe('Error restarting BLE advertising: $e');
        }
      });
    } else {
      _logger.severe('Maximum broadcast retry attempts reached');
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
      
      // Cancel any retry timer
      _broadcastRetryTimer?.cancel();
      _broadcastRetryTimer = null;
    } catch (e) {
      _logger.warning('Error stopping BLE advertising: $e');
    }
  }
  
  /// Clean up resources
  void dispose() {
    stopBroadcast();
    _broadcastRetryTimer?.cancel();
    _lastBroadcastMessage = null;
    _logger.info('Disposed BlePeripheralService');
  }
}
