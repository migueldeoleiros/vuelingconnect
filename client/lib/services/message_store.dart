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
  // Track when each message was received
  final Map<String, int> _receivedTime = {};
  // Track recent broadcasts for logging/display
  final List<String> _recentBroadcastLogs = [];
  
  // Configuration
  static const int MAX_HOP_COUNT = 5;
  static const int BROADCAST_INTERVAL_MS = 5000; // 5 seconds between broadcasts
  static const int MAX_MESSAGES_TO_RELAY = 10; // Maximum number of messages to consider for relay
  static const int MAX_LOG_ENTRIES = 20; // Maximum number of log entries to keep
  static const int MESSAGE_EXPIRY_MS = 3600000; // Messages expire after 1 hour
  
  // Broadcast rotation
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
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
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if this is a new message or has a lower hop count
    bool isNewMessage = !_messages.containsKey(messageId);
    bool hasLowerHopCount = !isNewMessage && _messages[messageId]!.hopCount > message.hopCount;
    
    if (isNewMessage || hasLowerHopCount) {
      if (isNewMessage) {
        _logger.info('Adding new message: $messageId with hop count: ${message.hopCount}');
        _receivedTime[messageId] = now;
      } else {
        _logger.info('Updating message: $messageId with lower hop count: ${message.hopCount}');
      }
      
      _messages[messageId] = message;
      
      // If auto-relay is enabled, ensure the broadcast timer is running
      if (_isAutoRelayEnabled && _broadcastTimer == null) {
        _startBroadcastTimer();
      }
    } else {
      _logger.fine('Ignoring duplicate message with higher or equal hop count: $messageId');
    }
  }
  
  /// Get messages to broadcast based on recency, hop count, and last broadcast time
  List<BleMessage> getMessagesToRelay() {
    if (_messages.isEmpty) return [];
    
    // Filter messages that haven't reached max hop count
    var eligibleMessages = _messages.values
        .where((msg) => msg.hopCount < MAX_HOP_COUNT)
        .toList();
    
    if (eligibleMessages.isEmpty) return [];
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Sort by a combination of factors:
    // 1. Time since last broadcast (prioritize messages not broadcast recently)
    // 2. Recency of message (newer messages get higher priority)
    // 3. Hop count (lower hop count gets higher priority)
    eligibleMessages.sort((a, b) {
      // First prioritize by time since last broadcast
      int lastBroadcastA = _lastBroadcastTime[a.messageId] ?? 0;
      int lastBroadcastB = _lastBroadcastTime[b.messageId] ?? 0;
      
      // If a message has never been broadcast, give it highest priority
      if (lastBroadcastA == 0 && lastBroadcastB > 0) return -1;
      if (lastBroadcastB == 0 && lastBroadcastA > 0) return 1;
      
      // Otherwise prioritize messages that haven't been broadcast recently
      int timeSinceLastA = now - lastBroadcastA;
      int timeSinceLastB = now - lastBroadcastB;
      int timeCompare = timeSinceLastB.compareTo(timeSinceLastA);
      if (timeCompare != 0) return timeCompare;
      
      // Then prioritize by recency (newer messages first)
      int messageTimeCompare = b.timestamp.compareTo(a.timestamp);
      if (messageTimeCompare != 0) return messageTimeCompare;
      
      // Finally by hop count (lower hop count first)
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
    
    // Start the cleanup timer
    _startCleanupTimer();
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
    
    if (_cleanupTimer != null) {
      _cleanupTimer!.cancel();
      _cleanupTimer = null;
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
    
    // Reset index if it's out of bounds (can happen if messages were removed)
    if (_currentIndex >= messages.length) {
      _currentIndex = 0;
    }
    
    // Get the current message to broadcast
    BleMessage message = messages[_currentIndex];
    
    // Create a new message with incremented hop count instead of modifying the original
    BleMessage updatedMessage = message.incrementHopCount();
    
    try {
      String logMessage = _getMessageDescription(updatedMessage);
      _logger.info('Broadcasting message: ${updatedMessage.messageId} with hop count: ${updatedMessage.hopCount}');
      _addBroadcastLog('Broadcasting: $logMessage (hop: ${updatedMessage.hopCount})');
      
      await _peripheralService.broadcastMessage(updatedMessage.encode());
      
      // Update last broadcast time
      _lastBroadcastTime[message.messageId] = DateTime.now().millisecondsSinceEpoch;
      
      // Store the updated message with incremented hop count
      _messages[message.messageId] = updatedMessage;
      
      // Increment index for next broadcast
      _currentIndex = (_currentIndex + 1) % messages.length;
    } catch (e) {
      _logger.severe('Error broadcasting message: $e');
      _addBroadcastLog('Error broadcasting message: $e');
    }
  }
  
  /// Start the cleanup timer to remove expired messages
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5), 
      (_) => _cleanupExpiredMessages()
    );
    _logger.info('Started message cleanup timer with interval: 5 minutes');
  }
  
  /// Remove expired messages from the store
  void _cleanupExpiredMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredMessageIds = <String>[];
    
    // Find expired messages
    _messages.forEach((id, message) {
      final messageTimestamp = message.timestamp * 1000; // Convert to milliseconds
      if (now - messageTimestamp > MESSAGE_EXPIRY_MS) {
        expiredMessageIds.add(id);
      }
    });
    
    // Remove expired messages
    for (final id in expiredMessageIds) {
      _messages.remove(id);
      _lastBroadcastTime.remove(id);
      _receivedTime.remove(id);
    }
    
    if (expiredMessageIds.isNotEmpty) {
      _logger.info('Removed ${expiredMessageIds.length} expired messages');
      _addBroadcastLog('Removed ${expiredMessageIds.length} expired messages');
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
    
    // Add to the beginning of the list for newest first
    _recentBroadcastLogs.insert(0, logEntry);
    if (_recentBroadcastLogs.length > MAX_LOG_ENTRIES) {
      _recentBroadcastLogs.removeLast();
    }
    
    // Send to stream for UI updates
    _broadcastLogController.add(logEntry);
  }
  
  /// Clear all stored messages
  void clearMessages() {
    _messages.clear();
    _lastBroadcastTime.clear();
    _receivedTime.clear();
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
