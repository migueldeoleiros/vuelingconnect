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
  final Map<String, int> _recentMessageIds = {}; // Map messageId to timestamp
  static const int _maxRecentMessages = 100; // Number of messages to track
  static const int _messageExpiryMs = 60000; // 1 minute expiry for duplicate detection
  
  // Retry mechanism for scan failures
  Timer? _scanRetryTimer;
  static const int _scanRetryIntervalMs = 5000; // 5 seconds between retries
  static const int _maxScanRetries = 3;
  int _scanRetryCount = 0;

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
    
    // Reset retry count
    _scanRetryCount = 0;
    
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
                _logger.info('Discovered VuelingConnect data: ${msd.data.length} bytes, RSSI: ${event.rssi}');
                
                // Process the message to check if it's a duplicate
                try {
                  final message = BleMessage.decode(msd.data);
                  final messageId = message.messageId;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  
                  // Check if we've seen this message ID recently
                  if (_recentMessageIds.containsKey(messageId)) {
                    final lastSeen = _recentMessageIds[messageId]!;
                    final timeSince = now - lastSeen;
                    
                    // If we've seen this message recently, ignore it
                    if (timeSince < _messageExpiryMs) {
                      _logger.fine('Rejected duplicate message with ID: $messageId (seen ${timeSince}ms ago)');
                      continue;
                    }
                    
                    // If it's been a while, update the timestamp and process it again
                    _recentMessageIds[messageId] = now;
                  } else {
                    // Add to recent messages
                    _recentMessageIds[messageId] = now;
                    
                    // Clean up old entries if we have too many
                    if (_recentMessageIds.length > _maxRecentMessages) {
                      _cleanupOldMessages();
                    }
                  }
                  
                  // Pass the data to subscribers
                  _dataController.add(msd.data);
                  _logger.info('Processed message with ID: $messageId, hop count: ${message.hopCount}');
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
          _restartScanningIfNeeded();
        },
      );
      
      // Start scanning
      await _manager.startDiscovery();
      _isScanning = true;
      _logger.info('Started BLE discovery');
      
      // Set up periodic scan restart to prevent Android from throttling
      _setupPeriodicScanRestart();
    } catch (e) {
      _logger.severe('Failed to start BLE discovery: $e');
      _restartScanningIfNeeded();
      rethrow;
    }
  }
  
  /// Clean up old message entries
  void _cleanupOldMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredIds = <String>[];
    
    // Find expired messages
    _recentMessageIds.forEach((id, timestamp) {
      if (now - timestamp > _messageExpiryMs) {
        expiredIds.add(id);
      }
    });
    
    // Remove expired messages
    for (final id in expiredIds) {
      _recentMessageIds.remove(id);
    }
    
    // If we still have too many, remove the oldest ones
    if (_recentMessageIds.length > _maxRecentMessages) {
      final sortedEntries = _recentMessageIds.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      final toRemove = sortedEntries.length - _maxRecentMessages;
      for (int i = 0; i < toRemove; i++) {
        _recentMessageIds.remove(sortedEntries[i].key);
      }
    }
  }
  
  /// Set up periodic scan restart to prevent Android from throttling
  void _setupPeriodicScanRestart() {
    // Cancel any existing timer
    _scanRetryTimer?.cancel();
    
    // Restart scanning every 30 seconds to prevent Android from throttling
    _scanRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isScanning) {
        _logger.info('Performing periodic scan restart to prevent throttling');
        try {
          await stopDiscovery();
          await Future.delayed(const Duration(milliseconds: 500));
          await startDiscovery();
        } catch (e) {
          _logger.warning('Error during periodic scan restart: $e');
        }
      }
    });
  }
  
  /// Restart scanning if needed after an error
  void _restartScanningIfNeeded() {
    if (_scanRetryCount < _maxScanRetries) {
      _scanRetryCount++;
      _logger.info('Attempting to restart scanning (retry $_scanRetryCount of $_maxScanRetries)');
      
      // Cancel any existing timer
      _scanRetryTimer?.cancel();
      
      // Try to restart after a delay
      _scanRetryTimer = Timer(Duration(milliseconds: _scanRetryIntervalMs), () async {
        try {
          // Make sure we're stopped first
          await stopDiscovery();
          await Future.delayed(const Duration(milliseconds: 500));
          await startDiscovery();
        } catch (e) {
          _logger.severe('Error restarting BLE discovery: $e');
        }
      });
    } else {
      _logger.severe('Maximum scan retry attempts reached');
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
      
      // Cancel any retry timer
      _scanRetryTimer?.cancel();
      _scanRetryTimer = null;
    } catch (e) {
      _logger.warning('Error stopping BLE discovery: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    stopDiscovery();
    _dataController.close();
    _recentMessageIds.clear();
    _scanRetryTimer?.cancel();
    _logger.info('Disposed BleCentralService');
  }
}
