import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE central for scanning manufacturer-specific advertisements
class BleCentralService {
  final CentralManager _manager = CentralManager();
  final Logger _logger = Logger('BleCentralService');

  StreamSubscription<DiscoveredEventArgs>? _discoverSub;
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  bool _isScanning = false;
  
  // Store hashes of recently processed messages to avoid duplicates
  final Set<String> _recentMessageHashes = {};
  static const int _maxRecentMessages = 50; // Limit the size of the set to prevent memory issues

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
                
                // Check if this is a duplicate message
                if (!_isDuplicateMessage(msd.data)) {
                  _dataController.add(msd.data);
                } else {
                  _logger.info('Rejected duplicate BLE message');
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

  /// Check if a message is a duplicate by computing a simple hash
  bool _isDuplicateMessage(Uint8List data) {
    // Create a simple hash of the message data
    final hash = _computeMessageHash(data);
    
    // Check if we've seen this hash before
    if (_recentMessageHashes.contains(hash)) {
      return true;
    }
    
    // Add to recent messages and maintain size limit
    _recentMessageHashes.add(hash);
    if (_recentMessageHashes.length > _maxRecentMessages) {
      _recentMessageHashes.remove(_recentMessageHashes.first);
    }
    
    return false;
  }
  
  /// Compute a simple hash for a message
  String _computeMessageHash(Uint8List data) {
    // Simple hash function - convert bytes to hex string
    return data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
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
    _recentMessageHashes.clear();
    _logger.info('Disposed BleCentralService');
  }
}
