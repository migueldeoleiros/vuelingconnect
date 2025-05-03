import 'dart:convert';
import 'dart:typed_data';

enum MsgType { flightStatus, alert }

enum FlightStatus { scheduled, departed, arrived, delayed, cancelled }

enum AlertMessage { evacuation, fire, medical, aliens }

class BleMessage {
  final MsgType msgType;
  final String? flightNumber; // Only for FlightStatus
  final FlightStatus? status; // Only for FlightStatus
  final AlertMessage? alertMessage; // Only for AlertMessage
  final int timestamp; // Epoch seconds

  BleMessage.flightStatus({
    required this.flightNumber,
    required this.status,
    required this.timestamp,
  }) : msgType = MsgType.flightStatus,
       alertMessage = null;

  BleMessage.alert({required this.alertMessage, required this.timestamp})
    : msgType = MsgType.alert,
      flightNumber = null,
      status = null;

  /// Encodes the message into a compact binary format for BLE advertisement.
  Uint8List encode() {
    List<int> bytes = [];
    bytes.add(msgType.index); // 1 byte
    if (msgType == MsgType.flightStatus) {
      // Flight number: encode as ASCII, max 8 bytes, padded with 0
      List<int> flightBytes = ascii.encode(flightNumber!).toList();
      if (flightBytes.length > 8) {
        flightBytes = flightBytes.sublist(0, 8);
      }
      while (flightBytes.length < 8) {
        flightBytes.add(0);
      }
      bytes.addAll(flightBytes); // 8 bytes
      bytes.add(status!.index); // 1 byte
    } else {
      // For alert messages, just store the enum index
      bytes.add(alertMessage!.index); // 1 byte
    }
    // Timestamp: 4 bytes, big-endian
    bytes.addAll(_intToBytes(timestamp, 4));
    return Uint8List.fromList(bytes);
  }

  static List<int> _intToBytes(int value, int length) {
    // Big-endian
    return List.generate(
      length,
      (i) => (value >> (8 * (length - i - 1))) & 0xFF,
    );
  }

  /// Decodes a BLE message from a Uint8List.
  static BleMessage decode(Uint8List data) {
    int idx = 0;
    MsgType msgType = MsgType.values[data[idx++]];
    if (msgType == MsgType.flightStatus) {
      // Flight number: 8 bytes ASCII, strip padding zeros
      List<int> flightBytes = data.sublist(idx, idx + 8);
      String flightNumber = ascii.decode(
        flightBytes.where((b) => b != 0).toList(),
      );
      idx += 8;
      FlightStatus status = FlightStatus.values[data[idx++]];
      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      return BleMessage.flightStatus(
        flightNumber: flightNumber,
        status: status,
        timestamp: timestamp,
      );
    } else {
      // Alert message: read enum index
      AlertMessage alertMessage = AlertMessage.values[data[idx++]];
      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      return BleMessage.alert(alertMessage: alertMessage, timestamp: timestamp);
    }
  }

  static int _bytesToInt(List<int> bytes) {
    int value = 0;
    for (int b in bytes) {
      value = (value << 8) | b;
    }
    return value;
  }
}

// Example test function (can be run in main.dart or here for quick test)
void testBleMessage() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // FlightStatus example
  var msg1 = BleMessage.flightStatus(
    flightNumber: "VY2383",
    status: FlightStatus.delayed,
    timestamp: now,
  );
  var encoded1 = msg1.encode();
  var decoded1 = BleMessage.decode(encoded1);
  print(
    'Original1: msgType=${msg1.msgType}, flightNumber=${msg1.flightNumber}, status=${msg1.status}, timestamp=${msg1.timestamp}',
  );
  print(
    'Decoded1:  msgType=${decoded1.msgType}, flightNumber=${decoded1.flightNumber}, status=${decoded1.status}, timestamp=${decoded1.timestamp}',
  );

  // Alert example
  var msg3 = BleMessage.alert(
    alertMessage: AlertMessage.evacuation,
    timestamp: now,
  );
  var encoded3 = msg3.encode();
  var decoded3 = BleMessage.decode(encoded3);
  print(
    'Original3: msgType=${msg3.msgType}, alertMessage=${msg3.alertMessage}, timestamp=${msg3.timestamp}',
  );
  print(
    'Decoded3:  msgType=${decoded3.msgType}, alertMessage=${decoded3.alertMessage}, timestamp=${decoded3.timestamp}',
  );
}
