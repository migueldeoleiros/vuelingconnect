import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble_message.dart';

/// BLE central for scanning manufacturer-specific advertisements
class BleCentralService {
  final CentralManager _manager = CentralManager();
  final Logger _logger = Logger('BleCentralService');

  StreamSubscription<DiscoveredEventArgs>? _discoverSub;
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  bool _isScanning = false;
  
  // Store message IDs of recently processed messages to avoid duplicates
  final Set<String> _recentMessageIds = {};
  static const int _maxRecentMessages = 100; // Increased to handle more messages

  /// Stream of raw manufacturer data bytes (id=0xFFFF)
  Stream<Uint8List> get dataStream => _dataController.stream;
  
  /// Whether the device is currently scanning
  bool get isScanning => _isScanning;

  /// Starts BLE discovery (scanning) for advertisements
  Future<void> startDiscovery() async {
    if (_isScanning) {
      _logger.info('Already scanning, ignoring startDiscovery call');
      return;
    }
    
    // Check permissions on Android
    if (Platform.isAndroid) {
      bool hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        _logger.severe('Missing required Bluetooth permissions, cannot start scanning');
        throw Exception('Missing required Bluetooth permissions');
      }
    }
    
    try {
      // Listen to discovered events
      _discoverSub = _manager.discovered.listen(
        (event) {
          // Log device information for debugging
          _logger.fine('Discovered device with RSSI: ${event.rssi}');
          
          // Check for manufacturer data
          if (event.advertisement.manufacturerSpecificData.isNotEmpty) {
            for (final msd in event.advertisement.manufacturerSpecificData) {
              if (msd.id == 0xFFFF) {
                _logger.info('Discovered VuelingConnect data: ${msd.data.length} bytes');
                
                // Process the message to check if it's a duplicate
                try {
                  final message = BleMessage.decode(msd.data);
                  final messageId = message.messageId;
                  
                  // Check if we've seen this message ID before
                  if (_recentMessageIds.contains(messageId)) {
                    _logger.info('Rejected duplicate message with ID: $messageId');
                  } else {
                    // Add to recent messages and maintain size limit
                    _recentMessageIds.add(messageId);
                    if (_recentMessageIds.length > _maxRecentMessages) {
                      _recentMessageIds.remove(_recentMessageIds.first);
                    }
                    
                    // Pass the data to subscribers
                    _dataController.add(msd.data);
                    _logger.info('Processed new message with ID: $messageId, hop count: ${message.hopCount}');
                  }
                } catch (e) {
                  _logger.warning('Error decoding BLE message: $e');
                  // If we can't decode it, just pass it through
                  _dataController.add(msd.data);
                }
              }
            }
          }
        },
        onError: (error) {
          _logger.severe('Error in BLE discovery: $error');
        },
      );
      
      // Start scanning with a more aggressive configuration
      await _manager.startDiscovery();
      _isScanning = true;
      _logger.info('Started BLE discovery');
    } catch (e) {
      _logger.severe('Failed to start BLE discovery: $e');
      rethrow;
    }
  }

  /// Check and request Bluetooth permissions
  Future<bool> _checkAndRequestPermissions() async {
    _logger.info('Checking Bluetooth permissions');
    
    // Check if we have the necessary permissions
    bool hasBluetoothScan = await Permission.bluetoothScan.isGranted;
    bool hasBluetoothConnect = await Permission.bluetoothConnect.isGranted;
    bool hasLocation = await Permission.location.isGranted;

    // If any permission is missing, request all of them
    if (!hasBluetoothScan || !hasBluetoothConnect || !hasLocation) {
      _logger.info('Requesting Bluetooth permissions');
      
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      
      // Check if all permissions were granted
      return statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
             statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
    }
    
    return true;
  }

  /// Stops BLE discovery
  Future<void> stopDiscovery() async {
    if (!_isScanning) {
      _logger.info('Not scanning, ignoring stopDiscovery call');
      return;
    }
    
    try {
      await _manager.stopDiscovery();
      await _discoverSub?.cancel();
      _discoverSub = null;
      _isScanning = false;
      _logger.info('Stopped BLE discovery');
    } catch (e) {
      _logger.warning('Error stopping BLE discovery: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    stopDiscovery();
    _dataController.close();
    _recentMessageIds.clear();
    _logger.info('Disposed BleCentralService');
  }
}
