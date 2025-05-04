import 'package:flutter/foundation.dart';

class BluetoothStateProvider with ChangeNotifier {
  bool _isSourceDevice = false;
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isAutoRelayEnabled = false;

  bool get isSourceDevice => _isSourceDevice;
  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  bool get isAutoRelayEnabled => _isAutoRelayEnabled;

  void setSourceDevice(bool value) {
    _isSourceDevice = value;
    notifyListeners();
  }

  void setScanning(bool value) {
    _isScanning = value;
    notifyListeners();
  }

  void setAdvertising(bool value) {
    _isAdvertising = value;
    notifyListeners();
  }
  
  void setAutoRelayEnabled(bool value) {
    _isAutoRelayEnabled = value;
    notifyListeners();
  }
}
