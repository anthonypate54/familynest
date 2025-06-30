import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_config.dart';

// Callback type for message handlers
typedef WebSocketMessageHandler = void Function(Map<String, dynamic> data);

// Callback type for connection status changes
typedef ConnectionStatusHandler = void Function(bool isConnected);

class WebSocketService extends ChangeNotifier {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  StompClient? _stompClient;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Store subscriptions by topic
  final Map<String, List<WebSocketMessageHandler>> _subscriptions = {};

  // Connection status listeners
  final List<ConnectionStatusHandler> _connectionListeners = [];

  // Connection retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// Initialize and connect to WebSocket
  Future<void> initialize() async {
    if (_isConnecting || _isConnected) {
      debugPrint('🔌 WebSocket: Already connecting or connected');
      return;
    }

    _isConnecting = true;
    notifyListeners();

    try {
      final baseUrl = AppConfig().baseUrl;
      final wsUrl = '$baseUrl/ws';
      debugPrint('🔌 WebSocket: Connecting to $wsUrl');

      _stompClient = StompClient(
        config: StompConfig.SockJS(
          url: wsUrl,
          onConnect: _onConnect,
          onWebSocketError: _onError,
          onDisconnect: _onDisconnect,
        ),
      );

      _stompClient!.activate();
    } catch (e) {
      debugPrint('❌ WebSocket: Error initializing: $e');
      _handleConnectionFailure();
    }
  }

  /// Handle successful connection
  void _onConnect(StompFrame frame) {
    debugPrint('✅ WebSocket: Connected successfully');
    _isConnected = true;
    _isConnecting = false;
    _retryCount = 0;
    notifyListeners();
    _notifyConnectionListeners(true);

    // Resubscribe to all topics
    _resubscribeToAllTopics();
  }

  /// Handle connection errors
  void _onError(dynamic error) {
    debugPrint('❌ WebSocket: Connection error: $error');
    _handleConnectionFailure();
  }

  /// Handle disconnection
  void _onDisconnect(StompFrame frame) {
    debugPrint('🔌 WebSocket: Disconnected');
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
    _notifyConnectionListeners(false);

    // Attempt to reconnect
    _scheduleReconnect();
  }

  /// Handle connection failure
  void _handleConnectionFailure() {
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
    _notifyConnectionListeners(false);

    if (_retryCount < _maxRetries) {
      _scheduleReconnect();
    } else {
      debugPrint('❌ WebSocket: Max retry attempts reached');
    }
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    _retryCount++;
    debugPrint(
      '🔄 WebSocket: Scheduling reconnect attempt $_retryCount/$_maxRetries',
    );

    Future.delayed(_retryDelay, () {
      if (!_isConnected && !_isConnecting) {
        initialize();
      }
    });
  }

  /// Subscribe to a topic with a message handler
  void subscribe(String topic, WebSocketMessageHandler handler) {
    debugPrint('📡 WebSocket: Subscribing to $topic');

    // Add handler to subscriptions
    if (!_subscriptions.containsKey(topic)) {
      _subscriptions[topic] = [];
    }
    _subscriptions[topic]!.add(handler);

    // Subscribe to topic if connected
    if (_isConnected && _stompClient != null) {
      _subscribeToTopic(topic);
    }
  }

  /// Unsubscribe from a topic
  void unsubscribe(String topic, WebSocketMessageHandler handler) {
    debugPrint('📡 WebSocket: Unsubscribing from $topic');

    if (_subscriptions.containsKey(topic)) {
      _subscriptions[topic]!.remove(handler);
      if (_subscriptions[topic]!.isEmpty) {
        _subscriptions.remove(topic);
      }
    }
  }

  /// Subscribe to a specific topic on the WebSocket
  void _subscribeToTopic(String topic) {
    if (_stompClient == null || !_isConnected) return;

    _stompClient!.subscribe(
      destination: topic,
      callback: (StompFrame frame) {
        if (frame.body != null) {
          _handleMessage(topic, frame.body!);
        }
      },
    );

    debugPrint('✅ WebSocket: Subscribed to $topic');
  }

  /// Resubscribe to all topics after reconnection
  void _resubscribeToAllTopics() {
    for (String topic in _subscriptions.keys) {
      _subscribeToTopic(topic);
    }
  }

  /// Handle incoming messages for a topic
  void _handleMessage(String topic, String body) {
    try {
      debugPrint('📨 WebSocket: Received message on $topic: $body');
      final jsonData = jsonDecode(body);

      // Notify all handlers for this topic
      if (_subscriptions.containsKey(topic)) {
        for (var handler in _subscriptions[topic]!) {
          try {
            handler(jsonData);
          } catch (e) {
            debugPrint('❌ WebSocket: Error in message handler for $topic: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ WebSocket: Error parsing message from $topic: $e');
      debugPrint('Raw message: $body');
    }
  }

  /// Add connection status listener
  void addConnectionListener(ConnectionStatusHandler listener) {
    _connectionListeners.add(listener);
  }

  /// Remove connection status listener
  void removeConnectionListener(ConnectionStatusHandler listener) {
    _connectionListeners.remove(listener);
  }

  /// Notify all connection listeners
  void _notifyConnectionListeners(bool isConnected) {
    for (var listener in _connectionListeners) {
      try {
        listener(isConnected);
      } catch (e) {
        debugPrint('❌ WebSocket: Error in connection listener: $e');
      }
    }
  }

  /// Send a message to a topic
  void sendMessage(String destination, Map<String, dynamic> message) {
    if (!_isConnected || _stompClient == null) {
      debugPrint('❌ WebSocket: Cannot send message - not connected');
      return;
    }

    try {
      final messageBody = jsonEncode(message);
      _stompClient!.send(destination: destination, body: messageBody);
      debugPrint('📤 WebSocket: Sent message to $destination: $messageBody');
    } catch (e) {
      debugPrint('❌ WebSocket: Error sending message: $e');
    }
  }

  /// Disconnect and cleanup
  void disconnect() {
    debugPrint('🔌 WebSocket: Disconnecting');
    _stompClient?.deactivate();
    _stompClient = null;
    _isConnected = false;
    _isConnecting = false;
    _subscriptions.clear();
    _connectionListeners.clear();
    _retryCount = 0;
    notifyListeners();
  }

  /// Get connection status string
  String get connectionStatus {
    if (_isConnecting) return 'Connecting...';
    if (_isConnected) return 'Connected';
    return 'Disconnected';
  }
}
