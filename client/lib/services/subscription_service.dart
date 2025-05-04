import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage flight subscriptions
class SubscriptionService extends ChangeNotifier {
  final Logger _logger = Logger('SubscriptionService');
  final Set<String> _subscribedFlights = {};
  
  // Stream controller for subscription events
  final StreamController<Map<String, dynamic>> _subscriptionEventController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  /// Stream of subscription events
  Stream<Map<String, dynamic>> get subscriptionEvents => _subscriptionEventController.stream;
  
  /// Get all subscribed flight numbers
  Set<String> get subscribedFlights => Set.unmodifiable(_subscribedFlights);
  
  /// Check if a flight is subscribed
  bool isSubscribed(String flightNumber) {
    return _subscribedFlights.contains(flightNumber);
  }
  
  /// Subscribe to a flight
  Future<void> subscribeToFlight(String flightNumber) async {
    if (_subscribedFlights.contains(flightNumber)) {
      return; // Already subscribed
    }
    
    _subscribedFlights.add(flightNumber);
    _logger.info('Subscribed to flight: $flightNumber');
    notifyListeners();
    
    // Save to persistent storage
    await _saveSubscriptions();
    
    // Emit subscription event
    _subscriptionEventController.add({
      'type': 'subscribe',
      'flight_number': flightNumber,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Unsubscribe from a flight
  Future<void> unsubscribeFromFlight(String flightNumber) async {
    if (!_subscribedFlights.contains(flightNumber)) {
      return; // Not subscribed
    }
    
    _subscribedFlights.remove(flightNumber);
    _logger.info('Unsubscribed from flight: $flightNumber');
    notifyListeners();
    
    // Save to persistent storage
    await _saveSubscriptions();
    
    // Emit unsubscription event
    _subscriptionEventController.add({
      'type': 'unsubscribe',
      'flight_number': flightNumber,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Check if a flight update should trigger a notification
  bool shouldNotify(Map<String, dynamic> flightUpdate) {
    final flightNumber = flightUpdate['flight_number'];
    return flightNumber != null && _subscribedFlights.contains(flightNumber);
  }
  
  /// Load subscriptions from persistent storage
  Future<void> loadSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSubscriptions = prefs.getStringList('flight_subscriptions');
      
      if (savedSubscriptions != null) {
        _subscribedFlights.clear();
        _subscribedFlights.addAll(savedSubscriptions);
        _logger.info('Loaded ${_subscribedFlights.length} flight subscriptions');
        notifyListeners();
      }
    } catch (e) {
      _logger.severe('Error loading flight subscriptions: $e');
    }
  }
  
  /// Save subscriptions to persistent storage
  Future<void> _saveSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('flight_subscriptions', _subscribedFlights.toList());
      _logger.info('Saved ${_subscribedFlights.length} flight subscriptions');
    } catch (e) {
      _logger.severe('Error saving flight subscriptions: $e');
    }
  }
  
  /// Clean up resources
  @override
  void dispose() {
    _subscriptionEventController.close();
    super.dispose();
  }
}
