import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// BLE peripheral for raw data advertisement
class BlePeripheralService {
  final PeripheralManager _manager = PeripheralManager();
  final Logger _logger = Logger('BlePeripheralService');

  /// Broadcasts custom bytes via BLE advertisement
  Future<void> broadcastMessage(Uint8List message) async {
    final adv = Advertisement(
      name: 'TestDevice',
      manufacturerSpecificData: [
        ManufacturerSpecificData(id: 0xFFFF, data: message),
      ],
    );
    await _manager.startAdvertising(adv);
    _logger.info('Started BLE advertising');
  }

  /// Stops BLE advertising
  Future<void> stopBroadcast() async {
    await _manager.stopAdvertising();
    _logger.info('Stopped BLE advertising');
  }
}
