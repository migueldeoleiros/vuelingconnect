import 'dart:convert';
import 'dart:typed_data';

enum MsgType { flightStatus, info, alert }

enum FlightStatus {
  scheduled,
  departed,
  arrived,
  delayed,
  cancelled,
}

class BleMessage {
  final MsgType msgType;
  final String? flightNumber; // Only for FlightStatus
  final FlightStatus? status; // Only for FlightStatus
  final String? message;      // Only for info/alert
  final int timestamp;        // Epoch seconds

  BleMessage.flightStatus({
    required this.flightNumber,
    required this.status,
    required this.timestamp,
  })  : msgType = MsgType.flightStatus,
        message = null;

  BleMessage.info({
    required this.message,
    required this.timestamp,
  })  : msgType = MsgType.info,
        flightNumber = null,
        status = null;

  BleMessage.alert({
    required this.message,
    required this.timestamp,
  })  : msgType = MsgType.alert,
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
      // info/alert: encode message as UTF-8, max 20 bytes
      List<int> msgBytes = utf8.encode(message!).toList();
      if (msgBytes.length > 20) {
        msgBytes = msgBytes.sublist(0, 20);
      }
      bytes.add(msgBytes.length); // 1 byte: length of message
      bytes.addAll(msgBytes); // up to 20 bytes
    }
    // Timestamp: 4 bytes, big-endian
    bytes.addAll(_intToBytes(timestamp, 4));
    return Uint8List.fromList(bytes);
  }

  static List<int> _intToBytes(int value, int length) {
    // Big-endian
    return List.generate(length, (i) => (value >> (8 * (length - i - 1))) & 0xFF);
  }

  /// Decodes a BLE message from a Uint8List.
  static BleMessage decode(Uint8List data) {
    int idx = 0;
    MsgType msgType = MsgType.values[data[idx++]];
    if (msgType == MsgType.flightStatus) {
      // Flight number: 8 bytes ASCII, strip padding zeros
      List<int> flightBytes = data.sublist(idx, idx + 8);
      String flightNumber = ascii.decode(flightBytes.where((b) => b != 0).toList());
      idx += 8;
      FlightStatus status = FlightStatus.values[data[idx++]];
      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      return BleMessage.flightStatus(
        flightNumber: flightNumber,
        status: status,
        timestamp: timestamp,
      );
    } else {
      int msgLen = data[idx++];
      String message = utf8.decode(data.sublist(idx, idx + msgLen));
      idx += msgLen;
      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      if (msgType == MsgType.info) {
        return BleMessage.info(message: message, timestamp: timestamp);
      } else {
        return BleMessage.alert(message: message, timestamp: timestamp);
      }
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
  print('Original1: msgType=${msg1.msgType}, flightNumber=${msg1.flightNumber}, status=${msg1.status}, timestamp=${msg1.timestamp}');
  print('Decoded1:  msgType=${decoded1.msgType}, flightNumber=${decoded1.flightNumber}, status=${decoded1.status}, timestamp=${decoded1.timestamp}');

  // Info example
  var msg2 = BleMessage.info(
    message: "Boarding at gate 12",
    timestamp: now,
  );
  var encoded2 = msg2.encode();
  var decoded2 = BleMessage.decode(encoded2);
  print('Original2: msgType=${msg2.msgType}, message=${msg2.message}, timestamp=${msg2.timestamp}');
  print('Decoded2:  msgType=${decoded2.msgType}, message=${decoded2.message}, timestamp=${decoded2.timestamp}');

  // Alert example
  var msg3 = BleMessage.alert(
    message: "Emergency evacuation!",
    timestamp: now,
  );
  var encoded3 = msg3.encode();
  var decoded3 = BleMessage.decode(encoded3);
  print('Original3: msgType=${msg3.msgType}, message=${msg3.message}, timestamp=${msg3.timestamp}');
  print('Decoded3:  msgType=${decoded3.msgType}, message=${decoded3.message}, timestamp=${decoded3.timestamp}');
}
