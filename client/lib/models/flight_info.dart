import 'dart:convert';
import 'dart:typed_data';

class FlightInfo {
  final String flightNumber;
  final String destination;
  final String gate;
  final DateTime departureTime;
  final String status; // "On Time", "Delayed", "Boarding", etc.
  final DateTime timestamp; // When this information was last updated

  FlightInfo({
    required this.flightNumber,
    required this.destination,
    required this.gate,
    required this.departureTime,
    required this.status,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // Convert to JSON representation
  Map<String, dynamic> toJson() {
    return {
      'flightNumber': flightNumber,
      'destination': destination,
      'gate': gate,
      'departureTime': departureTime.toIso8601String(),
      'status': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Create from JSON
  factory FlightInfo.fromJson(Map<String, dynamic> json) {
    return FlightInfo(
      flightNumber: json['flightNumber'],
      destination: json['destination'],
      gate: json['gate'],
      departureTime: DateTime.parse(json['departureTime']),
      status: json['status'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  // Convert to bytes for BLE transmission
  Uint8List toBytes() {
    final jsonString = jsonEncode(toJson());
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  // Create from bytes
  factory FlightInfo.fromBytes(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final json = jsonDecode(jsonString);
    return FlightInfo.fromJson(json);
  }

  // Helper to create a list of flights from bytes
  static List<FlightInfo> listFromBytes(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => FlightInfo.fromJson(json)).toList();
  }

  // Helper to convert a list to bytes
  static Uint8List listToBytes(List<FlightInfo> flights) {
    final jsonList = flights.map((flight) => flight.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    return Uint8List.fromList(utf8.encode(jsonString));
  }
}
