import 'dart:async';
import 'package:logging/logging.dart';
import '../ble_message.dart';
import 'ble_peripheral_service.dart';

/// Manages a store of messages for automatic relaying
class MessageStore {
  final Logger _logger = Logger('MessageStore');
  final BlePeripheralService _peripheralService;
  
  // Store messages with their unique IDs
  final Map<String, BleMessage> _messages = {};
  // Track last broadcast time for each message
  final Map<String, int> _lastBroadcastTime = {};
  // Track recent broadcasts for logging/display
  final List<String> _recentBroadcastLogs = [];
  
  // Configuration
  static const int MAX_HOP_COUNT = 5;
  static const int BROADCAST_INTERVAL_MS = 5000; // 5 seconds between broadcasts
  static const int MAX_MESSAGES_TO_RELAY = 10; // Maximum number of messages to consider for relay
  static const int MAX_LOG_ENTRIES = 20; // Maximum number of log entries to keep
  
  // Broadcast rotation
  Timer? _broadcastTimer;
  int _currentIndex = 0;
  bool _isAutoRelayEnabled = false;
  
  // Stream controller for broadcast logs
  final StreamController<String> _broadcastLogController = StreamController<String>.broadcast();
  
  MessageStore(this._peripheralService);
  
  /// Whether automatic relay is enabled
  bool get isAutoRelayEnabled => _isAutoRelayEnabled;
  
  /// Get all stored messages
  List<BleMessage> get allMessages => _messages.values.toList();
  
  /// Stream of broadcast log messages
  Stream<String> get broadcastLogStream => _broadcastLogController.stream;
  
  /// Get recent broadcast logs
  List<String> get recentBroadcastLogs => List.unmodifiable(_recentBroadcastLogs);
  
  /// Add a message to the store
  void addMessage(BleMessage message) {
    String messageId = message.messageId;
    
    // Only add if new or has a lower hop count for the same message
    if (!_messages.containsKey(messageId) || 
        _messages[messageId]!.hopCount > message.hopCount) {
      _logger.info('Adding/updating message: $messageId with hop count: ${message.hopCount}');
      _messages[messageId] = message;
      
      // If auto-relay is enabled, ensure the broadcast timer is running
      if (_isAutoRelayEnabled && _broadcastTimer == null) {
        _startBroadcastTimer();
      }
    } else {
      _logger.fine('Ignoring message with higher or equal hop count: $messageId');
    }
  }
  
  /// Get messages to broadcast based on recency and hop count
  List<BleMessage> getMessagesToRelay() {
    if (_messages.isEmpty) return [];
    
    // Filter messages that haven't reached max hop count
    var eligibleMessages = _messages.values
        .where((msg) => msg.hopCount < MAX_HOP_COUNT)
        .toList();
    
    if (eligibleMessages.isEmpty) return [];
    
    // Sort by timestamp (newer first) and hop count (lower first)
    eligibleMessages.sort((a, b) {
      // First prioritize by recency (newer messages first)
      int timeCompare = b.timestamp.compareTo(a.timestamp);
      if (timeCompare != 0) return timeCompare;
      
      // Then by hop count (lower hop count first)
      return a.hopCount.compareTo(b.hopCount);
    });
    
    // Return up to MAX_MESSAGES_TO_RELAY messages
    return eligibleMessages.take(MAX_MESSAGES_TO_RELAY).toList();
  }
  
  /// Start automatic broadcasting of messages
  void startAutoRelay() {
    if (_isAutoRelayEnabled) return;
    
    _isAutoRelayEnabled = true;
    _logger.info('Starting automatic message relay');
    _addBroadcastLog('Starting automatic message relay');
    
    if (_messages.isNotEmpty) {
      _startBroadcastTimer();
    } else {
      _logger.info('No messages to relay yet, timer will start when messages are added');
      _addBroadcastLog('No messages to relay yet, waiting for messages');
    }
  }
  
  /// Stop automatic broadcasting
  void stopAutoRelay() {
    if (!_isAutoRelayEnabled) return;
    
    _isAutoRelayEnabled = false;
    _logger.info('Stopping automatic message relay');
    _addBroadcastLog('Stopped automatic message relay');
    
    if (_broadcastTimer != null) {
      _broadcastTimer!.cancel();
      _broadcastTimer = null;
    }
  }
  
  /// Start the broadcast timer
  void _startBroadcastTimer() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(
      Duration(milliseconds: BROADCAST_INTERVAL_MS), 
      (_) => _broadcastNextMessage()
    );
    _logger.info('Started broadcast timer with interval: $BROADCAST_INTERVAL_MS ms');
  }
  
  /// Broadcast the next message in the rotation
  void _broadcastNextMessage() async {
    List<BleMessage> messages = getMessagesToRelay();
    if (messages.isEmpty) {
      _logger.fine('No messages to relay');
      return;
    }
    
    // Rotate through messages
    _currentIndex = (_currentIndex + 1) % messages.length;
    BleMessage message = messages[_currentIndex];
    
    // Increment hop count before broadcasting
    BleMessage updatedMessage = message.incrementHopCount();
    
    try {
      String logMessage = _getMessageDescription(updatedMessage);
      _logger.info('Broadcasting message: ${updatedMessage.messageId} with hop count: ${updatedMessage.hopCount}');
      _addBroadcastLog('Broadcasting: $logMessage (hop: ${updatedMessage.hopCount})');
      
      await _peripheralService.broadcastMessage(updatedMessage.encode());
      
      // Update last broadcast time
      _lastBroadcastTime[message.messageId] = DateTime.now().millisecondsSinceEpoch;
      
      // Update the message in the store with the incremented hop count
      _messages[message.messageId] = updatedMessage;
    } catch (e) {
      _logger.severe('Error broadcasting message: $e');
      _addBroadcastLog('Error broadcasting message: $e');
    }
  }
  
  /// Get a human-readable description of a message
  String _getMessageDescription(BleMessage message) {
    if (message.msgType == MsgType.flightStatus) {
      return 'Flight ${message.flightNumber} (${message.status.toString().split('.').last})';
    } else {
      return 'Alert: ${message.alertMessage.toString().split('.').last}';
    }
  }
  
  /// Add a log entry for broadcast activity
  void _addBroadcastLog(String log) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19); // HH:MM:SS
    final logEntry = '[$timestamp] $log';
    
    _recentBroadcastLogs.add(logEntry);
    if (_recentBroadcastLogs.length > MAX_LOG_ENTRIES) {
      _recentBroadcastLogs.removeAt(0);
    }
    
    // Send to stream for UI updates
    _broadcastLogController.add(logEntry);
  }
  
  /// Clear all stored messages
  void clearMessages() {
    _messages.clear();
    _lastBroadcastTime.clear();
    _logger.info('Cleared all messages from store');
    _addBroadcastLog('Cleared all messages from store');
  }
  
  /// Clean up resources
  void dispose() {
    stopAutoRelay();
    clearMessages();
    _broadcastLogController.close();
    _logger.info('Disposed MessageStore');
  }
}
