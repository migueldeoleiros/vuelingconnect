import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import '../models/flight_info.dart';

class BleCentralService {
  final _logger = Logger('BleCentralService');
  final List<FlightInfo> _flights = [];
  bool _isScanning = false;

  // Service and characteristic UUIDs - MUST match on all devices
  static const String FLIGHT_SERVICE_UUID =
      "9b1dfc9c-90a3-4c7a-9991-a2bccf5e15e3";
  static const String FLIGHT_CHARACTERISTIC_UUID =
      "79cda9a1-ceec-4156-baba-927d0b3e3cab";

  // Stream controllers to broadcast flight updates
  final _flightsStreamController =
      StreamController<List<FlightInfo>>.broadcast();
  Stream<List<FlightInfo>> get flightsStream => _flightsStreamController.stream;

  // Start scanning for BLE devices
  Future<void> startScan() async {
    if (_isScanning) return;

    _logger.info('Starting BLE scan');
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(FLIGHT_SERVICE_UUID)],
        timeout: const Duration(seconds: 30),
      );

      _isScanning = true;

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.advertisementData.serviceUuids.contains(
            FLIGHT_SERVICE_UUID,
          )) {
            _logger.info('Found flight info device: ${result.device.name}');
            _connectAndGetFlights(result.device);
          }
        }
      });
    } catch (e) {
      _logger.severe('Error starting BLE scan: $e');
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    _logger.info('Stopping BLE scan');
    try {
      await FlutterBluePlus.stopScan();
      _isScanning = false;
    } catch (e) {
      _logger.severe('Error stopping BLE scan: $e');
    }
  }

  // Connect to device and read flight data
  Future<void> _connectAndGetFlights(BluetoothDevice device) async {
    try {
      _logger.info('Connecting to ${device.name}');
      await device.connect();

      // Discover services
      _logger.info('Discovering services');
      List<BluetoothService> services = await device.discoverServices();

      // Find our flight service
      BluetoothService? flightService;
      for (var service in services) {
        if (service.uuid.toString() == FLIGHT_SERVICE_UUID) {
          flightService = service;
          break;
        }
      }

      if (flightService == null) {
        _logger.warning('Flight service not found on device');
        await device.disconnect();
        return;
      }

      // Find the characteristic within this service
      BluetoothCharacteristic? flightCharacteristic;
      for (var characteristic in flightService.characteristics) {
        if (characteristic.uuid.toString() == FLIGHT_CHARACTERISTIC_UUID) {
          flightCharacteristic = characteristic;
          break;
        }
      }

      if (flightCharacteristic == null) {
        _logger.warning('Flight characteristic not found in service');
        await device.disconnect();
        return;
      }

      // Read flight data
      final value = await flightCharacteristic.read();
      _processFlightData(value);

      // Subscribe to notifications
      await flightCharacteristic.setNotifyValue(true);
      flightCharacteristic.value.listen((value) {
        _processFlightData(value);
      });

      // Disconnect after a while to save battery (optional)
      await Future.delayed(const Duration(seconds: 10));
      await device.disconnect();
    } catch (e) {
      _logger.severe('Error connecting to device: $e');
    }
  }

  // Process received flight data
  void _processFlightData(List<int> data) {
    try {
      final flightList = FlightInfo.listFromBytes(data as Uint8List);

      // Update local flights, replacing outdated info with newer timestamp
      for (final newFlight in flightList) {
        final existingIndex = _flights.indexWhere(
          (f) => f.flightNumber == newFlight.flightNumber,
        );

        if (existingIndex >= 0) {
          // Only update if newer information
          if (_flights[existingIndex].timestamp.isBefore(newFlight.timestamp)) {
            _flights[existingIndex] = newFlight;
          }
        } else {
          // Add new flight
          _flights.add(newFlight);
        }
      }

      // Notify listeners
      _flightsStreamController.add(List.from(_flights));
    } catch (e) {
      _logger.severe('Error processing flight data: $e');
    }
  }

  // For cleanup
  void dispose() {
    _flightsStreamController.close();
  }
}
