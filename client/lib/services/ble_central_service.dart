import 'dart:async';
import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:logging/logging.dart';

/// BLE central for scanning manufacturer-specific advertisements
class BleCentralService {
  final CentralManager _manager = CentralManager();
  final Logger _logger = Logger('BleCentralService');

  StreamSubscription<DiscoveredEventArgs>? _discoverSub;
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();

  /// Stream of raw manufacturer data bytes (id=0xFFFF)
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// Starts BLE discovery (scanning) for advertisements
  Future<void> startDiscovery() async {
    // Listen to discovered events
    _discoverSub = _manager.discovered.listen((event) {
      for (final msd in event.advertisement.manufacturerSpecificData) {
        if (msd.id == 0xFFFF) {
          _logger.info('Discovered data: ${msd.data}');
          _dataController.add(msd.data);
        }
      }
    });
    await _manager.startDiscovery();
    _logger.info('Started BLE discovery');
  }

  /// Stops BLE discovery
  Future<void> stopDiscovery() async {
    await _manager.stopDiscovery();
    await _discoverSub?.cancel();
    _logger.info('Stopped BLE discovery');
  }

  /// Clean up resources
  void dispose() {
    _discoverSub?.cancel();
    _dataController.close();
  }
}
