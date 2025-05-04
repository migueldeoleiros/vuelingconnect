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
  final int hopCount; // Number of times this message has been relayed
  final int? eta; // Estimated Time of Arrival (epoch seconds), only for FlightStatus
  final String? destination; // Destination IATA code, only for FlightStatus
  final String? deviceId; // Optional device identifier for uniqueness

  BleMessage.flightStatus({
    required this.flightNumber,
    required this.status,
    required this.timestamp,
    this.hopCount = 0,
    this.eta,
    this.destination,
    this.deviceId,
  }) : msgType = MsgType.flightStatus,
       alertMessage = null;

  BleMessage.alert({
    required this.alertMessage,
    required this.timestamp,
    this.hopCount = 0,
    this.deviceId,
  }) : msgType = MsgType.alert,
       flightNumber = null,
       status = null,
       eta = null,
       destination = null;

  /// Creates a new message with incremented hop count
  BleMessage incrementHopCount() {
    if (msgType == MsgType.flightStatus) {
      return BleMessage.flightStatus(
        flightNumber: flightNumber,
        status: status,
        timestamp: timestamp,
        hopCount: hopCount + 1,
        eta: eta,
        destination: destination,
        deviceId: deviceId,
      );
    } else {
      return BleMessage.alert(
        alertMessage: alertMessage,
        timestamp: timestamp,
        hopCount: hopCount + 1,
        deviceId: deviceId,
      );
    }
  }

  /// Generates a message ID based on content (excluding hop count)
  String get messageId {
    // Create a unique identifier by combining content and timestamp
    if (msgType == MsgType.flightStatus) {
      return 'flight_${flightNumber}_${status!.index}_$timestamp';
    } else {
      return 'alert_${alertMessage!.index}_$timestamp';
    }
  }

  /// Encodes the message into a compact binary format for BLE advertisement.
  Uint8List encode() {
    List<int> bytes = [];
    bytes.add(msgType.index); // 1 byte
    bytes.add(hopCount); // 1 byte for hop count

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

      // Add ETA (4 bytes) if available, otherwise 0
      if (eta != null) {
        bytes.addAll(_intToBytes(eta!, 4)); // 4 bytes
      } else {
        bytes.addAll(_intToBytes(0, 4)); // 4 zeros if no ETA
      }

      // Destination: 3 bytes (IATA code, max 3 characters)
      if (destination != null) {
        List<int> destinationBytes = ascii.encode(destination!).toList();
        if (destinationBytes.length > 3) {
          destinationBytes = destinationBytes.sublist(0, 3);
        }
        while (destinationBytes.length < 3) {
          destinationBytes.add(0);
        }
        bytes.addAll(destinationBytes); // 3 bytes
      } else {
        bytes.addAll(_intToBytes(0, 3)); // 3 zeros if no destination
      }
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
    int hopCount = data[idx++]; // Read hop count

    if (msgType == MsgType.flightStatus) {
      // Flight number: 8 bytes ASCII, strip padding zeros
      List<int> flightBytes = data.sublist(idx, idx + 8);
      String flightNumber = ascii.decode(
        flightBytes.where((b) => b != 0).toList(),
      );
      idx += 8;
      FlightStatus status = FlightStatus.values[data[idx++]];

      // Read ETA if it exists
      int etaValue = _bytesToInt(data.sublist(idx, idx + 4));
      idx += 4;
      int? eta = (etaValue == 0) ? null : etaValue; // 0 means no ETA

      // Read destination if it exists
      String? destination;
      if (data.length > idx + 2) {
        List<int> destinationBytes = data.sublist(idx, idx + 3);
        destination = ascii.decode(
          destinationBytes.where((b) => b != 0).toList(),
        );
        idx += 3;
      }

      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      return BleMessage.flightStatus(
        flightNumber: flightNumber,
        status: status,
        timestamp: timestamp,
        hopCount: hopCount,
        eta: eta,
        destination: destination,
      );
    } else {
      // Alert message: read enum index
      AlertMessage alertMessage = AlertMessage.values[data[idx++]];
      int timestamp = _bytesToInt(data.sublist(idx, idx + 4));
      return BleMessage.alert(
        alertMessage: alertMessage,
        timestamp: timestamp,
        hopCount: hopCount,
      );
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
    eta: now + 3600, // ETA in 1 hour
    destination: "LAX",
  );
  var encoded1 = msg1.encode();
  var decoded1 = BleMessage.decode(encoded1);
  print(
    'Original1: msgType=${msg1.msgType}, flightNumber=${msg1.flightNumber}, status=${msg1.status}, timestamp=${msg1.timestamp}, eta=${msg1.eta}, hopCount=${msg1.hopCount}, destination=${msg1.destination}',
  );
  print(
    'Decoded1:  msgType=${decoded1.msgType}, flightNumber=${decoded1.flightNumber}, status=${decoded1.status}, timestamp=${decoded1.timestamp}, eta=${decoded1.eta}, hopCount=${decoded1.hopCount}, destination=${decoded1.destination}',
  );

  // Test hop count increment
  var relayedMsg = msg1.incrementHopCount();
  print(
    'Original hopCount: ${msg1.hopCount}, Relayed hopCount: ${relayedMsg.hopCount}',
  );

  // Test messageId
  print('Message ID: ${msg1.messageId}');

  // Alert example
  var msg3 = BleMessage.alert(
    alertMessage: AlertMessage.evacuation,
    timestamp: now,
  );
  var encoded3 = msg3.encode();
  var decoded3 = BleMessage.decode(encoded3);
  print(
    'Original3: msgType=${msg3.msgType}, alertMessage=${msg3.alertMessage}, timestamp=${msg3.timestamp}, hopCount=${msg3.hopCount}',
  );
  print(
    'Decoded3:  msgType=${decoded3.msgType}, alertMessage=${decoded3.alertMessage}, timestamp=${decoded3.timestamp}, hopCount=${decoded3.hopCount}',
  );
}
