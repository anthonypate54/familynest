import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import '../config/app_config.dart';
import '../models/message.dart';

// Callback type for message handlers
typedef WebSocketMessageHandler = void Function(Map<String, dynamic> data);

// Callback type for Message handlers
typedef MessageHandler = void Function(Message message);

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

  // Debug message listeners (for test screen)
  final List<WebSocketMessageHandler> _debugMessageListeners = [];

  // Connection retry logic with exponential backoff
  int _retryCount = 0;
  static const int _maxRetries = 10; // Increased from 3
  static const Duration _baseRetryDelay = Duration(seconds: 2); // Base delay
  static const Duration _maxRetryDelay = Duration(
    seconds: 60,
  ); // Cap at 1 minute

  // Connection health monitoring
  Timer? _healthCheckTimer;
  Timer? _reconnectTimer;
  DateTime? _lastHealthCheck;
  int _consecutiveFailures = 0;

  // Connection quality metrics
  int _messagesSent = 0;
  int _messagesReceived = 0;
  DateTime? _lastMessageTime;
  Duration _averageLatency = Duration.zero;

  // Enhanced monitoring
  DateTime? _lastSuccessfulPing;
  int _pingFailures = 0;
  static const Duration _maxIdleTime = Duration(
    minutes: 35,
  ); // Warn at 35 minutes

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// Enhanced connection with exponential backoff
  Future<void> initialize() async {
    if (_isConnecting || _isConnected) {
      debugPrint('🔌 WebSocket: Already connecting or connected');
      return;
    }

    _isConnecting = true;
    _safeNotifyListeners();

    try {
      final baseUrl = AppConfig().baseUrl;
      final wsUrl = '$baseUrl/ws';
      debugPrint(
        '🔌 WebSocket: Connecting to $wsUrl (attempt ${_retryCount + 1})',
      );

      _stompClient = StompClient(
        config: StompConfig.SockJS(
          url: wsUrl,
          onConnect: _onConnect,
          onWebSocketError: _onError,
          onDisconnect: _onDisconnect,
          heartbeatIncoming: const Duration(seconds: 120),
          heartbeatOutgoing: const Duration(seconds: 120),
        ),
      );

      _stompClient!.activate();
    } catch (e) {
      debugPrint('❌ WebSocket: Error initializing: $e');
      _handleConnectionFailure();
    }
  }

  /// Safe method to call notifyListeners outside of build phase
  void _safeNotifyListeners() {
    // Use Future.microtask to defer notifyListeners to avoid build phase issues
    Future.microtask(() {
      notifyListeners();
    });
  }

  /// Enhanced connection success handler
  void _onConnect(StompFrame frame) {
    debugPrint('✅ WebSocket: Connected successfully');
    _isConnected = true;
    _isConnecting = false;
    _retryCount = 0;
    _consecutiveFailures = 0;

    // Reset message tracking to prevent immediate idle detection
    _lastMessageTime = DateTime.now();

    _safeNotifyListeners();
    _notifyConnectionListeners(true);

    // Start health monitoring
    _startHealthMonitoring();

    // Resubscribe to all topics with a small delay to ensure connection is fully ready
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_isConnected && _stompClient != null) {
        _resubscribeToAllTopics();
      }
    });
  }

  /// Enhanced error handler
  void _onError(dynamic error) {
    debugPrint('❌ WebSocket: Connection error: $error');
    _consecutiveFailures++;
    _stopHealthMonitoring();
    _handleConnectionFailure();
  }

  /// Enhanced disconnect handler
  void _onDisconnect(StompFrame frame) {
    debugPrint('🔌 WebSocket: Disconnected');
    _isConnected = false;
    _isConnecting = false;
    _stopHealthMonitoring();
    _safeNotifyListeners();
    _notifyConnectionListeners(false);

    // Attempt to reconnect with exponential backoff
    _scheduleReconnectWithBackoff();
  }

  /// Enhanced failure handler
  void _handleConnectionFailure() {
    _isConnected = false;
    _isConnecting = false;
    _consecutiveFailures++;
    _safeNotifyListeners();
    _notifyConnectionListeners(false);

    if (_retryCount < _maxRetries) {
      _scheduleReconnectWithBackoff();
    } else {
      debugPrint('❌ WebSocket: Max retry attempts reached');
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnectWithBackoff() {
    _retryCount++;

    // Calculate exponential backoff delay
    final exponentialDelay = _baseRetryDelay * pow(2, _retryCount - 1);
    final cappedDelay =
        exponentialDelay > _maxRetryDelay ? _maxRetryDelay : exponentialDelay;

    // Add jitter to prevent thundering herd
    final jitter = Random().nextDouble() * 0.3; // 0-30% jitter
    final finalDelay = Duration(
      milliseconds: (cappedDelay.inMilliseconds * (1 + jitter)).round(),
    );

    debugPrint(
      '🔄 WebSocket: Scheduling reconnect attempt $_retryCount/$_maxRetries in ${finalDelay.inSeconds}s',
    );

    // Cancel any existing timer
    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(finalDelay, () {
      if (!_isConnected && !_isConnecting) {
        initialize();
      }
    });
  }

  /// Start health monitoring with periodic checks
  void _startHealthMonitoring() {
    _stopHealthMonitoring(); // Clear any existing timer

    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _performHealthCheck();
    });

    _lastHealthCheck = DateTime.now();
    debugPrint('💓 WebSocket: Health monitoring started');
  }

  /// Stop health monitoring
  void _stopHealthMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    debugPrint('💓 WebSocket: Health monitoring stopped');
  }

  /// Perform health check
  void _performHealthCheck() {
    if (!_isConnected || _stompClient == null) return;

    final now = DateTime.now();
    _lastHealthCheck = now;

    // Check if we've received any messages recently
    final timeSinceLastMessage =
        _lastMessageTime != null
            ? now.difference(_lastMessageTime!)
            : Duration(hours: 1);

    // Note: Removed aggressive idle detection as it was causing reconnection loops

    if (timeSinceLastMessage.inMinutes > 5) {
      debugPrint(
        '⚠️ WebSocket: No messages received in ${timeSinceLastMessage.inMinutes} minutes',
      );

      // Try sending a ping message
      _sendPing();
    }

    debugPrint(
      '💓 WebSocket: Health check - Connected: $_isConnected, Messages sent: $_messagesSent, received: $_messagesReceived',
    );
  }

  /// Send ping message for health check
  void _sendPing() {
    if (!_isConnected || _stompClient == null) return;

    try {
      final pingMessage = {
        'type': 'PING',
        'timestamp': DateTime.now().toIso8601String(),
      };

      _stompClient!.send(
        destination: '/app/ping',
        body: jsonEncode(pingMessage),
      );

      debugPrint('🏓 WebSocket: Sent ping message');
    } catch (e) {
      debugPrint('❌ WebSocket: Error sending ping: $e');
    }
  }

  /// Subscribe to a topic with a message handler
  void subscribe(String topic, WebSocketMessageHandler handler) {
    debugPrint('📡 WebSocket: Subscribing to $topic');

    // Add handler to subscriptions (prevent duplicates)
    if (!_subscriptions.containsKey(topic)) {
      _subscriptions[topic] = [];
    }

    // Check if this handler is already subscribed to prevent duplicates
    if (!_subscriptions[topic]!.contains(handler)) {
      _subscriptions[topic]!.add(handler);
      debugPrint(
        '✅ WebSocket: Added new handler for $topic (total: ${_subscriptions[topic]!.length})',
      );
    } else {
      debugPrint(
        '⚠️ WebSocket: Handler already exists for $topic, skipping duplicate',
      );
      return;
    }

    // Subscribe to topic if connected (only once per topic)
    if (_isConnected && _stompClient != null) {
      // Only subscribe to the STOMP topic if this is the first handler for this topic
      if (_subscriptions[topic]!.length == 1) {
        _subscribeToTopic(topic);
      } else {
        debugPrint(
          '📡 WebSocket: Already subscribed to $topic, reusing existing subscription',
        );
      }
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
    if (_stompClient == null || !_isConnected) {
      debugPrint('⚠️ WebSocket: Cannot subscribe to $topic - not connected');
      return;
    }

    try {
      _stompClient!.subscribe(
        destination: topic,
        callback: (StompFrame frame) {
          if (frame.body != null) {
            _handleMessage(topic, frame.body!);
          }
        },
      );

      debugPrint('✅ WebSocket: Subscribed to $topic');
    } catch (e) {
      debugPrint('❌ WebSocket: Failed to subscribe to $topic: $e');
      // Don't rethrow - this is expected during reconnection race conditions
      // The subscription will be retried on the next connection cycle
    }
  }

  /// Resubscribe to all topics after reconnection
  void _resubscribeToAllTopics() {
    for (String topic in _subscriptions.keys) {
      _subscribeToTopic(topic);
    }
  }

  /// Enhanced message handling with metrics
  void _handleMessage(String topic, String body) {
    try {
      _messagesReceived++;
      _lastMessageTime = DateTime.now();

      debugPrint('📨 WebSocket: Received message on $topic: $body');
      final jsonData = jsonDecode(body);

      // Handle pong responses
      if (jsonData['type'] == 'PONG') {
        debugPrint('🏓 WebSocket: Received pong response');
        return;
      }

      // Notify debug listeners with raw message data
      for (var debugListener in _debugMessageListeners) {
        try {
          debugListener({
            'topic': topic,
            'body': body,
            'data': jsonData,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint('❌ WebSocket: Error in debug message listener: $e');
        }
      }

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

    // Immediately notify the current connection status to the new listener
    // This fixes timing issues where listeners are added after connection is established
    try {
      listener(_isConnected);
    } catch (e) {
      debugPrint('❌ WebSocket: Error notifying new connection listener: $e');
    }
  }

  /// Remove connection status listener
  void removeConnectionListener(ConnectionStatusHandler listener) {
    _connectionListeners.remove(listener);
  }

  /// Add debug message listener (for test screen)
  void addDebugMessageListener(WebSocketMessageHandler listener) {
    _debugMessageListeners.add(listener);
    debugPrint('🔍 WebSocket: Added debug message listener');
  }

  /// Remove debug message listener
  void removeDebugMessageListener(WebSocketMessageHandler listener) {
    _debugMessageListeners.remove(listener);
    debugPrint('🔍 WebSocket: Removed debug message listener');
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

  /// Enhanced message sending with metrics
  void sendMessage(String destination, Map<String, dynamic> message) {
    if (!_isConnected || _stompClient == null) {
      debugPrint('❌ WebSocket: Cannot send message - not connected');
      return;
    }

    try {
      final messageBody = jsonEncode(message);
      _stompClient!.send(destination: destination, body: messageBody);

      _messagesSent++;
      debugPrint('📤 WebSocket: Sent message to $destination: $messageBody');
    } catch (e) {
      debugPrint('❌ WebSocket: Error sending message: $e');
    }
  }

  /// Enhanced disconnect with cleanup
  void disconnect() {
    debugPrint('🔌 WebSocket: Disconnecting');

    // Stop all timers
    _stopHealthMonitoring();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Disconnect client
    _stompClient?.deactivate();
    _stompClient = null;

    // Reset state
    _isConnected = false;
    _isConnecting = false;
    _retryCount = 0;
    _consecutiveFailures = 0;
    _subscriptions.clear();
    _connectionListeners.clear();

    // Reset metrics
    _messagesSent = 0;
    _messagesReceived = 0;
    _lastMessageTime = null;
    _lastHealthCheck = null;

    notifyListeners();
  }

  /// Get detailed connection status
  String get connectionStatus {
    if (_isConnecting) {
      return _retryCount > 0
          ? 'Reconnecting... (${_retryCount}/$_maxRetries)'
          : 'Connecting...';
    }
    if (_isConnected) {
      return 'Connected';
    }
    return _retryCount >= _maxRetries ? 'Connection Failed' : 'Disconnected';
  }

  /// Get connection quality info
  Map<String, dynamic> get connectionInfo {
    return {
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'retryCount': _retryCount,
      'maxRetries': _maxRetries,
      'consecutiveFailures': _consecutiveFailures,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'lastMessageTime': _lastMessageTime?.toIso8601String(),
      'lastHealthCheck': _lastHealthCheck?.toIso8601String(),
      'connectionStatus': connectionStatus,
    };
  }

  /// Force reconnection (for manual retry)
  Future<void> forceReconnect() async {
    debugPrint('🔄 WebSocket: Force reconnecting...');

    // Stop current connection
    _stompClient?.deactivate();
    _stompClient = null;
    _isConnected = false;
    _isConnecting = false;

    // Reset retry count for immediate retry
    _retryCount = 0;

    // Reconnect immediately
    await initialize();
  }

  // ===== MESSAGE LISTENER METHODS =====

  /// Add a message listener that subscribes to user-specific topics
  /// Returns Message objects parsed from the WebSocket data
  /// This is the new improved architecture where clients only need to subscribe to their own topics
  void addMessageListenerForUser(int userId, MessageHandler listener) {
    // Subscribe to DM messages for this specific user
    subscribe('/topic/dm/$userId', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing DM message: $e');
      }
    });

    // Subscribe to new messages for this user (separated from comments/reactions)
    // The backend will broadcast to this topic for all families the user belongs to
    subscribe('/user/$userId/messages', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing new message: $e');
      }
    });

    // Subscribe to test messages
    subscribe('/topic/test', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing test message: $e');
      }
    });
  }

  /// Legacy method for backward compatibility
  /// @deprecated Use addMessageListenerForUser(userId, listener) instead
  @Deprecated('Use addMessageListenerForUser(userId, listener) instead')
  void addMessageListenerForUserLegacy(
    int userId,
    int? familyId,
    MessageHandler listener,
  ) {
    // Subscribe to DM messages for this specific user
    subscribe('/topic/dm/$userId', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing DM message: $e');
      }
    });

    // Subscribe to family messages for this specific family (if user has one)
    // NOTE: This is legacy support - new architecture uses user-specific topics
    if (familyId != null) {
      subscribe('/family/$familyId', (data) {
        try {
          final message = Message.fromJson(data);
          listener(message);
        } catch (e) {
          debugPrint('❌ WebSocket: Error parsing family message: $e');
        }
      });
    }

    // Subscribe to test messages
    subscribe('/topic/test', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing test message: $e');
      }
    });
  }

  /// Add a general message listener (for backward compatibility)
  void addMessageListener(MessageHandler listener) {
    // Subscribe to test messages
    subscribe('/topic/test', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing test message: $e');
      }
    });
  }

  /// Subscribe to family messages for a specific family
  void subscribeToFamilyMessages(int familyId, MessageHandler handler) {
    final topic = '/family/$familyId';
    debugPrint('📡 WebSocket: Subscribing to family messages: $topic');
    subscribe(topic, (data) {
      try {
        final message = Message.fromJson(data);
        handler(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing family message: $e');
      }
    });
  }

  /// Subscribe to DM messages for a specific user
  void subscribeToDMMessages(int userId, MessageHandler handler) {
    final topic = '/topic/dm/$userId';
    debugPrint('📡 WebSocket: Subscribing to DM messages: $topic');
    subscribe(topic, (data) {
      try {
        final message = Message.fromJson(data);
        handler(message);
      } catch (e) {
        debugPrint('❌ WebSocket: Error parsing DM message: $e');
      }
    });
  }

  /// Send a DM message (same as existing)
  Future<void> sendDMMessage({
    required int senderId,
    required int recipientId,
    required String content,
  }) async {
    final message = {
      'senderId': senderId,
      'recipientId': recipientId,
      'content': content,
    };

    sendMessage('/app/dm/message', message);
  }

  /// Send a family message (duplicate of DM but for family)
  Future<void> sendFamilyMessage({
    required int senderId,
    required int familyId,
    required String content,
  }) async {
    final message = {
      'senderId': senderId,
      'familyId': familyId,
      'content': content,
    };

    sendMessage('/app/family/message', message);
  }

  /// Send a family reaction (duplicate of DM but for family)
  Future<void> sendFamilyReaction({
    required int senderId,
    required int familyId,
    required int messageId,
    required String reactionType,
  }) async {
    final message = {
      'senderId': senderId,
      'familyId': familyId,
      'messageId': messageId,
      'reactionType': reactionType,
    };

    sendMessage('/app/family/reaction', message);
  }
}
