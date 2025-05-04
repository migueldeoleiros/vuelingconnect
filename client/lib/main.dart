import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:prueba_app/ble_message.dart';
import 'package:prueba_app/views/points_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/bluetooth_state_provider.dart';
import 'services/ble_central_service.dart';
import 'services/ble_peripheral_service.dart';
import 'package:prueba_app/views/points_view.dart';
import 'services/message_store.dart';
import 'theme.dart';
import 'utils/date_utils.dart';
import 'utils/string_utils.dart';
import 'views/bluetooth_view.dart';
import 'widgets/message_cards.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

const MethodChannel platform = MethodChannel(
  'dexterx.dev/flutter_local_notifications_example',
);

const String portName = 'notification_send_port';


void main() async {
  // Set up logging
  // testBleMessage();
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('Error: ${record.error}\nStack trace: ${record.stackTrace}');
    }
  });

  // Ensure Flutter is initialized before using platform channels
  WidgetsFlutterBinding.ensureInitialized();

  await Permission.notification.request();

  // Request permissions on startup for Android
  if (Platform.isAndroid) {
    await _requestBluetoothPermissions();
  }

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: selectNotificationStream.add,
    onDidReceiveBackgroundNotificationResponse: null,
  );

  runApp(const MyApp());
}

// Request Bluetooth permissions required for Android 12+
Future<void> _requestBluetoothPermissions() async {
  // Request all required permissions
  Map<Permission, PermissionStatus> statuses =
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ].request();

  // Log the permission statuses
  statuses.forEach((permission, status) {
    print('$permission: $status');
  });

  // Try to enable Bluetooth if it's not already on
  try {
    if (!await FlutterBluePlus.isOn) {
      await FlutterBluePlus.turnOn();
    }
  } catch (e) {
    print('Error turning on Bluetooth: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'your_channel_id', // Change this to a unique ID
          'Local Notifications',
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      'Hello, Flutter!',
      'This is your first local notification.',
      platformChannelSpecifics,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<BleCentralService>(
          create: (_) => BleCentralService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<BlePeripheralService>(create: (_) => BlePeripheralService()),
        ChangeNotifierProvider(create: (_) => BluetoothStateProvider()),
        ProxyProvider<BlePeripheralService, MessageStore>(
          create:
              (context) => MessageStore(
                Provider.of<BlePeripheralService>(context, listen: false),
              ),
          update:
              (_, peripheralService, previous) =>
                  previous ?? MessageStore(peripheralService),
          dispose: (_, store) => store.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'Vueling Connect',
        theme: getLightTheme(),
        darkTheme: getDarkTheme(),
        themeMode: ThemeMode.dark, // Force dark mode
        home: const MyHomePage(title: 'Vueling Connect'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<Uint8List>? _bleCentralSubscription;
  Timer? _apiPollingTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Flight tracking
  final TextEditingController _flightNumberController = TextEditingController();
  Map<String, dynamic>? _flightInfo;
  bool _isLoading = false;
  String _errorMessage = '';
  String _serverAddress = 'localhost';
  String _serverPort = '8000';

  // Stored flight information
  List<Map<String, dynamic>> _savedFlights = [];

  // Alerts information
  final List<Map<String, dynamic>> _activeAlerts = [];

  final _bluetoothViewKey = GlobalKey<BluetoothViewState>();

  @override
  void initState() {
    super.initState();
      _loadPoints();

     _pointTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          setState(() {
            _points += 10;
            _isScaled = true;
            _showFloatingPlus = true;
          });

          _savePoints();

          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() {
                _isScaled = false;
              });
            }
          });

          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _showFloatingPlus = false;
              });
            }
          });
        }
      });

    _initBluetooth();
    _loadSavedFlights();
    _loadServerSettings();
    _initBleCentralListener();
  }

  Future<void> _loadSavedFlights() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFlightsJson = prefs.getString('savedFlights');

    if (savedFlightsJson != null) {
      setState(() {
        _savedFlights = List<Map<String, dynamic>>.from(
          (jsonDecode(savedFlightsJson) as List).map(
            (flight) => Map<String, dynamic>.from(flight as Map),
          ),
        );
      });
    }
  }

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverAddress = prefs.getString('serverAddress') ?? 'localhost';
      _serverPort = prefs.getString('serverPort') ?? '8000';
    });
  }

  Future<void> _saveFlights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedFlights', jsonEncode(_savedFlights));
  }

  Future<void> _saveServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', _serverAddress);
    await prefs.setString('serverPort', _serverPort);
  }

  void _initBleCentralListener() {
    // Get the BLE central service from the provider
    final centralService = Provider.of<BleCentralService>(
      context,
      listen: false,
    );

    // Get the message store for automatic relaying
    final messageStore = Provider.of<MessageStore>(context, listen: false);

    // Subscribe to the BLE central data stream
    _bleCentralSubscription = centralService.dataStream.listen((data) {
      try {
        // Decode the BLE message
        final bleMessage = BleMessage.decode(Uint8List.fromList(data));

        // Add the message to the store for potential relaying
        messageStore.addMessage(bleMessage);

        // Process the message based on its type
        if (bleMessage.msgType == MsgType.flightStatus &&
            bleMessage.flightNumber != null) {
          // Convert BLE flight status message to our format
          final flight = {
            'flight_number': bleMessage.flightNumber,
            'flight_status': bleMessage.status.toString().split('.').last,
            'timestamp':
                DateTime.fromMillisecondsSinceEpoch(
                  bleMessage.timestamp * 1000,
                ).toIso8601String(),
            'flight_message': _getFlightStatusMessage(
              bleMessage.status.toString().split('.').last,
            ),
            'source': 'bluetooth', // Mark the source as bluetooth
            'hop_count': bleMessage.hopCount, // Include hop count
          };
          _updateFlightInfo(flight);
        } else if (bleMessage.msgType == MsgType.alert &&
            bleMessage.alertMessage != null) {
          // Convert BLE alert message to our format
          final alert = {
            'alert_type': bleMessage.alertMessage.toString().split('.').last,
            'timestamp':
                DateTime.fromMillisecondsSinceEpoch(
                  bleMessage.timestamp * 1000,
                ).toIso8601String(),
            'message': _getAlertMessage(
              bleMessage.alertMessage.toString().split('.').last,
            ),
            'source': 'bluetooth', // Mark the source as bluetooth
            'hop_count': bleMessage.hopCount, // Include hop count
          };
          _addAlert(alert);
        }
      } catch (e) {
        print('Error processing BLE message: $e');
      }
    });
  }

  Future<void> _initBluetooth() async {
    // Habilita logs
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);

    // Verifica soporte de Bluetooth
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      return;
    }

    // Escucha cambios en el estado del adaptador
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
      BluetoothAdapterState state,
    ) {
      print('Bluetooth state: $state');
      if (state == BluetoothAdapterState.on) {
        // Aquí podrías iniciar el escaneo, etc.
        _playSound('a.mp3');
        print("Bluetooth está activado");
      } else {
        _playSound('b.mp3');
        print("Bluetooth desactivado o sin permisos");
      }
    });

    // En Android, intenta activar Bluetooth automáticamente
    if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  Future<void> _playSound(String path) async {
    try {
      await _audioPlayer.play(AssetSource(path));
    } catch (e) {
      print("Error al reproducir sonido: $e");
    }
  }

  Future<void> _fetchFlightInfo() async {
    final flightNumber = _flightNumberController.text.trim();

    setState(() {
      _isLoading = true;
      _flightInfo = null;
      _errorMessage = '';
    });

    // If a flight number was specified, filter the existing flights
    if (flightNumber.isNotEmpty) {
      // Find the requested flight in saved flights
      final matchingFlight = _savedFlights.firstWhere(
        (flight) => flight['flight_number'] == flightNumber,
        orElse: () => <String, dynamic>{},
      );

      setState(() {
        _flightInfo = matchingFlight.isEmpty ? null : matchingFlight;
        if (_flightInfo == null) {
          _errorMessage = 'Flight not found';
        }
        _isLoading = false;
      });
    } else {
      // No flight number specified, just show all flights
      setState(() {
        _flightInfo = null;
        _isLoading = false;
      });
    }
  }

  // This method is called periodically when source device is on
  Future<void> _fetchFlightInfoFromAPI() async {
    // Use 10.0.2.2 instead of localhost when running on Android emulator
    String host = _serverAddress;
    if (!kIsWeb && Platform.isAndroid && host == 'localhost') {
      // 10.0.2.2 is the special IP for host machine when using Android emulator
      host = '10.0.2.2';
    }

    final apiUrl = 'http://$host:$_serverPort/flight-status';
    print('Connecting to API: $apiUrl');

    // Get the message store for automatic relaying
    final messageStore = Provider.of<MessageStore>(context, listen: false);

    // Get reference to the Bluetooth view to send API messages
    final bluetoothViewState = _bluetoothViewKey.currentState;

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final List<dynamic> messages = jsonDecode(response.body);

        // Process messages by type
        for (var msg in messages) {
          String msgType = msg['msg_type'];

          if (msgType == 'flightStatus') {
            // Only process if we have the minimum required fields
            if (msg['flight_number'] != null) {
              // Extract timestamp
              int timestamp =
                  (msg['timestamp'] is int)
                      ? msg['timestamp']
                      : int.parse(msg['timestamp'].toString());

              // Create BLE message for relay
              final bleMessage = BleMessage.flightStatus(
                flightNumber: msg['flight_number'],
                status: _getFlightStatusEnum(msg['status']),
                timestamp: timestamp,
              );

              // Add to message store for relaying
              messageStore.addMessage(bleMessage);

              // Convert to our format
              final flight = {
                'flight_number': msg['flight_number'],
                'flight_status': msg['status'] ?? 'unknown',
                'timestamp':
                    DateTime.fromMillisecondsSinceEpoch(
                      timestamp * 1000,
                    ).toIso8601String(),
                'flight_message': _getFlightStatusMessage(msg['status']),
                'source': 'api', // Mark the source as API
                'msg_type': 'flight',
              };
              _updateFlightInfo(flight);

              // Send to Bluetooth view if available
              if (bluetoothViewState != null) {
                bluetoothViewState.addApiMessage(flight);
              }
            }
          } else if (msgType == 'alert') {
            // Only process if we have the minimum required fields
            if (msg['alert_type'] != null && msg['timestamp'] != null) {
              // Extract timestamp
              int timestamp =
                  (msg['timestamp'] is int)
                      ? msg['timestamp']
                      : int.parse(msg['timestamp'].toString());

              // Create BLE message for relay
              final bleMessage = BleMessage.alert(
                alertMessage: _getAlertMessageEnum(msg['alert_type']),
                timestamp: timestamp,
              );

              // Add to message store for relaying
              messageStore.addMessage(bleMessage);

              // Process alert
              final alert = {
                'alert_type': msg['alert_type'],
                'timestamp':
                    DateTime.fromMillisecondsSinceEpoch(
                      timestamp * 1000,
                    ).toIso8601String(),
                'message': _getAlertMessage(msg['alert_type']),
                'source': 'api', // Mark the source as API
                'msg_type': 'alert',
              };
              _addAlert(alert);

              // Send to Bluetooth view if available
              if (bluetoothViewState != null) {
                bluetoothViewState.addApiMessage(alert);
              }
            }
          }
        }

        print(
          'Successfully fetched and processed ${messages.length} messages from API',
        );
      } else {
        print('Failed to fetch flight info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching from API: $e');
    }
  }

  // Helper to convert string to FlightStatus enum
  FlightStatus _getFlightStatusEnum(String? status) {
    if (status == null) return FlightStatus.scheduled;

    switch (status.toLowerCase()) {
      case 'departed':
        return FlightStatus.departed;
      case 'arrived':
        return FlightStatus.arrived;
      case 'delayed':
        return FlightStatus.delayed;
      case 'cancelled':
        return FlightStatus.cancelled;
      case 'scheduled':
      default:
        return FlightStatus.scheduled;
    }
  }

  // Helper to convert string to AlertMessage enum
  AlertMessage _getAlertMessageEnum(String? alertType) {
    if (alertType == null) return AlertMessage.evacuation;

    switch (alertType.toLowerCase()) {
      case 'medical':
        return AlertMessage.medical;
      case 'fire':
        return AlertMessage.fire;
      case 'aliens':
        return AlertMessage.aliens;
      case 'evacuation':
      default:
        return AlertMessage.evacuation;
    }
  }

  // This method is called by the Bluetooth view when source device is toggled
  void _handleSourceDeviceToggled(bool isSourceDevice) {
    // Get the provider to ensure state is in sync
    final provider = Provider.of<BluetoothStateProvider>(
      context,
      listen: false,
    );

    // Make sure provider state matches what we received
    if (provider.isSourceDevice != isSourceDevice) {
      provider.setSourceDevice(isSourceDevice);
    }

    // Start or stop API polling based on source device status
    if (isSourceDevice) {
      // Start polling the API every 10 seconds
      _apiPollingTimer?.cancel();
      _apiPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _fetchFlightInfoFromAPI();
      });

      // Fetch immediately on toggle
      _fetchFlightInfoFromAPI();
    } else {
      // Stop polling when source device is turned off
      _apiPollingTimer?.cancel();
      _apiPollingTimer = null;
    }
  }

  // Helper to get flight status message
  String _getFlightStatusMessage(String? status) {
    if (status == null) return 'Flight status unknown.';

    switch (status) {
      case 'scheduled':
        return 'Your flight is scheduled to depart as planned.';
      case 'departed':
        return 'Your flight has departed.';
      case 'arrived':
        return 'Your flight has arrived at the destination.';
      case 'delayed':
        return 'Your flight is delayed. Please check the departure board.';
      case 'cancelled':
        return 'Your flight has been cancelled. Please contact Vueling staff.';
      default:
        return 'Flight status unknown.';
    }
  }

  // Helper to get alert message
  String _getAlertMessage(String? alertType) {
    if (alertType == null) return 'Unknown alert.';

    switch (alertType) {
      case 'medical':
        return 'Medical emergency alert. If you are a doctor or medical professional, please identify yourself to cabin crew.';
      case 'evacuation':
        return 'EMERGENCY! Please prepare for evacuation and follow crew instructions immediately!';
      case 'fire':
        return 'EMERGENCY! Fire alert. Please remain calm and follow crew instructions.';
      case 'aliens':
        return 'ALERT: Unexpected visitors detected. This is not a drill.';
      default:
        return 'Unknown alert.';
    }
  }

  // Update existing flight or add new one if it doesn't exist
  void _updateFlightInfo(Map<String, dynamic> newFlight) {
    // Validate that we have at least a flight number
    final flightNumber = newFlight['flight_number'];
    if (flightNumber == null) {
      print('Cannot update flight info: Missing flight number');
      return;
    }

    final index = _savedFlights.indexWhere(
      (flight) => flight['flight_number'] == flightNumber,
    );

    // Make sure all required fields exist with defaults if needed
    final updatedFlight = {
      'flight_number': flightNumber,
      'flight_status': newFlight['flight_status'] ?? 'unknown',
      'timestamp': newFlight['timestamp'] ?? DateTime.now().toIso8601String(),
      'flight_message':
          newFlight['flight_message'] ??
          _getFlightStatusMessage(newFlight['flight_status']),
      'source':
          newFlight['source'] ?? 'api', // Default to 'api' if not specified
    };

    if (index != -1) {
      // Flight exists, check if it's identical to avoid duplicates
      final existingFlight = _savedFlights[index];
      if (_isIdenticalFlight(existingFlight, updatedFlight)) {
        print(
          'Rejecting identical flight update for ${updatedFlight['flight_number']}',
        );
        return;
      }

      // Not identical, check timestamp
      try {
        final DateTime existingTimestamp = DateTime.parse(
          _savedFlights[index]['timestamp'] ?? '',
        );
        final DateTime newTimestamp = DateTime.parse(
          updatedFlight['timestamp'],
        );

        if (newTimestamp.isAfter(existingTimestamp)) {
          setState(() {
            _savedFlights[index] = updatedFlight;

            // Only update _flightInfo if we're currently viewing this specific flight
            if (_flightInfo != null &&
                _flightInfo!['flight_number'] == flightNumber) {
              _flightInfo = updatedFlight;
            }
          });
        } else {
          // Use existing flight info if it's newer
          setState(() {
            // Only update _flightInfo if we're currently viewing this specific flight
            if (_flightInfo != null &&
                _flightInfo!['flight_number'] == flightNumber) {
              _flightInfo = _savedFlights[index];
            }
          });
        }
      } catch (e) {
        // If there's an issue with timestamp parsing, just update with new info
        setState(() {
          _savedFlights[index] = updatedFlight;

          // Only update _flightInfo if we're currently viewing this specific flight
          if (_flightInfo != null &&
              _flightInfo!['flight_number'] == flightNumber) {
            _flightInfo = updatedFlight;
          }
        });
        print('Error parsing timestamps: $e');
      }
    } else {
      // New flight, add it
      setState(() {
        _savedFlights.add(updatedFlight);

        // Don't automatically set _flightInfo to the new flight
        // This allows the "All Flights" view to remain visible
      });
    }

    _saveFlights();
  }

  // Get flights sorted by timestamp (most recent first)
  List<Map<String, dynamic>> _getSortedFlights() {
    final sortedFlights = List<Map<String, dynamic>>.from(_savedFlights);
    sortedFlights.sort((a, b) {
      try {
        final DateTime timeA = DateTime.parse(a['timestamp'] ?? '');
        final DateTime timeB = DateTime.parse(b['timestamp'] ?? '');
        return timeB.compareTo(timeA); // Descending order (newest first)
      } catch (e) {
        print('Error parsing timestamps during sorting: $e');
        return 0;
      }
    });
    return sortedFlights;
  }

  // Check if two flight objects are identical in their key properties
  bool _isIdenticalFlight(
    Map<String, dynamic> flight1,
    Map<String, dynamic> flight2,
  ) {
    return flight1['flight_number'] == flight2['flight_number'] &&
        flight1['flight_status'] == flight2['flight_status'] &&
        flight1['timestamp'] == flight2['timestamp'];
  }

  // Save an alert
  void _addAlert(Map<String, dynamic> alert) {
    // Make sure we have the minimum required fields
    if (alert['alert_type'] == null) {
      print('Cannot add alert: Missing alert type');
      return;
    }

    // Ensure all required fields have values
    final safeAlert = {
      'alert_type': alert['alert_type'],
      'timestamp': alert['timestamp'] ?? DateTime.now().toIso8601String(),
      'message': alert['message'] ?? _getAlertMessage(alert['alert_type']),
      'source': alert['source'] ?? 'api', // Default to 'api' if not specified
    };

    // Check if this alert is a duplicate of an existing one
    final isDuplicate = _activeAlerts.any(
      (existingAlert) => _isIdenticalAlert(existingAlert, safeAlert),
    );

    if (isDuplicate) {
      print('Rejecting identical alert of type ${safeAlert['alert_type']}');
      return;
    }

    setState(() {
      _activeAlerts.add(safeAlert);
    });

    // Show a notification for the new alert
    _showAlertNotification(safeAlert);
  }

  // Show a notification for an alert
  Future<void> _showAlertNotification(Map<String, dynamic> alert) async {
    // Get alert details
    final alertType = alert['alert_type'];
    final message = alert['message'] ?? 'Alert received';

    // Configure notification details
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'alerts_channel',
          'Alerts Channel',
          channelDescription: 'Channel for important flight alerts',
          importance: Importance.max,
          priority: Priority.high,
          // Use default sound and vibration
          playSound: true,
          enableVibration: true,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    // Show the notification
    await flutterLocalNotificationsPlugin.show(
      // Use timestamp as unique ID to avoid overwriting
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'ALERT: ${capitalizeFirstLetter(alertType)}',
      message,
      platformDetails,
    );
  }

  // Check if two alert objects are identical in their key properties
  bool _isIdenticalAlert(
    Map<String, dynamic> alert1,
    Map<String, dynamic> alert2,
  ) {
    return alert1['alert_type'] == alert2['alert_type'] &&
        alert1['timestamp'] == alert2['timestamp'] &&
        alert1['message'] == alert2['message'];
  }

  // Show alert details dialog
  void _showAlertDialog(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  getAlertIcon(alert['alert_type']),
                  color: getAlertColor(alert['alert_type']),
                ),
                const SizedBox(width: 8),
                const Text('Alert'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['message'] ?? 'No message available',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time: ${formatDateTime(alert['timestamp'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _activeAlerts.removeWhere(
                      (a) =>
                          a['alert_type'] == alert['alert_type'] &&
                          a['timestamp'] == alert['timestamp'],
                    );
                  });
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Dismiss'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _points = prefs.getInt('points') ?? 0;
    });
  }

  Future<void> _savePoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('points', _points);
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _bleCentralSubscription?.cancel();
    _apiPollingTimer?.cancel();
    _flightNumberController.dispose();
    _pointTimer.cancel();
    super.dispose();
  }
  int _points = 0;
  bool _isScaled = false;
  bool _showFloatingPlus = false;
  late Timer _pointTimer;
  
  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.black,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            onPressed: _navigateToBluetoothView,
            tooltip: 'Bluetooth Mesh',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showServerSettings,
            tooltip: 'Server Settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Alert section if there are active alerts
            if (_activeAlerts.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => _showAlertsDialog(),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AlertCard(
                alert: _activeAlerts.last,
                onTap: () => _showAlertDialog(_activeAlerts.last),
              ),
              const SizedBox(height: 16),
            ],

            // Flight tracker section
            Text(
              'Flight Tracker',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _flightNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Flight Number (e.g., VY2375)',
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _fetchFlightInfo,
                  child: const Text('Filter Flights'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_flightNumberController.text.isNotEmpty)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    _flightNumberController.clear();
                    _fetchFlightInfo();
                  },
                  icon: const Icon(Icons.list),
                  label: const Text('View All Flights'),
                ),
              ),
            const SizedBox(height: 16),

            // Flight info display
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage.isNotEmpty)
              SelectableText(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              )
            else if (_flightInfo != null)
              FlightCard(flight: _flightInfo!, isExpanded: true)
            else if (_savedFlights.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Flights',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _getSortedFlights().length,
                        itemBuilder: (context, index) {
                          final flight = _getSortedFlights()[index];
                          return FlightCard(
                            flight: flight,
                            onTap: () {
                              setState(() {
                                _flightNumberController.text =
                                    flight['flight_number'];
                                _flightInfo = flight;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Text(
                  'No flights available. Try connecting to the server or checking a specific flight.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNavigationBar(),
    );
  }

  Widget _bottomNavigationBar() {
      return SafeArea(
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$_points pts',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.all(0),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PointsView()),
                    );
                  },
                  child: AnimatedScale(
                    scale: _isScaled ? 1.25 : 1.0,
                    duration: const Duration(milliseconds: 450),
                    child: const Icon(
                      Icons.airplane_ticket,
                      size: 64,
                      color: Color.fromARGB(255, 255, 255, 0),
                    ),
                  ),
                ),

                // +10 flotante animado
                if (_showFloatingPlus)
                  const Positioned(
                    top: -30,
                    child: _FloatingPlus(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  void _showAlertsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Active Alerts'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child:
                  _activeAlerts.isEmpty
                      ? const Center(child: Text('No active alerts'))
                      : ListView.builder(
                        itemCount: _activeAlerts.length,
                        itemBuilder: (context, index) {
                          return AlertCard(
                            alert: _activeAlerts[index],
                            onTap: () {
                              Navigator.pop(context);
                              _showAlertDialog(_activeAlerts[index]);
                            },
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (_activeAlerts.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _activeAlerts.clear();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
            ],
          ),
    );
  }

  void _showServerSettings() {
    final addressController = TextEditingController(text: _serverAddress);
    final portController = TextEditingController(text: _serverPort);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Server Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Server Address',
                    hintText: 'localhost or IP address',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    labelText: 'Server Port',
                    hintText: '8000',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _serverAddress = addressController.text;
                    _serverPort = portController.text;
                  });
                  // Save to shared preferences
                  _saveServerSettings();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Server set to: $_serverAddress:$_serverPort',
                      ),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }


  void _showSavedFlights() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Saved Flights'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  _savedFlights.isEmpty
                      ? const Text('No saved flights')
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _savedFlights.length,
                        itemBuilder: (context, index) {
                          final flight = _savedFlights[index];
                          return ListTile(
                            title: Text('Flight ${flight['flight_number']}'),
                            subtitle: Text(
                              'Status: ${capitalizeFirstLetter(flight['flight_status'])}\n'
                              'Last Updated: ${formatDateTime(flight['timestamp'])}',
                            ),
                            onTap: () {
                              _flightNumberController.text =
                                  flight['flight_number'];
                              setState(() {
                                _flightInfo = flight;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  

  void _navigateToBluetoothView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => BluetoothView(
              savedFlights: _savedFlights,
              onSourceDeviceToggled: _handleSourceDeviceToggled,
              key: _bluetoothViewKey,
            ),
      ),
    );
  }
  

}

class _FloatingPlus extends StatefulWidget {
  const _FloatingPlus({Key? key}) : super(key: key);

  @override
  State<_FloatingPlus> createState() => _FloatingPlusState();
}

class _FloatingPlusState extends State<_FloatingPlus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _position;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _position = Tween<double>(begin: 0, end: -40).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _position.value),
            child: child,
          ),
        );
      },
      child: const Text(
        '+10',
        style: TextStyle(
          fontSize: 30,
          color: Colors.yellow,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

}