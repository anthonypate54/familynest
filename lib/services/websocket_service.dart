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
  bool _isGracefulDisconnect =
      false; // Flag to prevent auto-reconnect during manual disconnect

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

  // Enhanced monitoring with industry-standard intervals
  DateTime? _lastSuccessfulPing;
  int _pingFailures = 0;

  // Progressive ping intervals based on idle time
  static const Duration _initialIdleThreshold = Duration(
    minutes: 15,
  ); // Start pinging after 15min idle
  static const Duration _shortPingInterval = Duration(
    minutes: 5,
  ); // Ping every 5min for first phase
  static const Duration _longIdleThreshold = Duration(
    minutes: 30,
  ); // Switch to longer interval after 30min
  static const Duration _longPingInterval = Duration(
    minutes: 10,
  ); // Ping every 10min for extended idle

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// Enhanced connection with exponential backoff
  Future<void> initialize() async {
    if (_isConnecting || _isConnected) {
      debugPrint(
        '🔌 WebSocket: Already connecting or connected (connecting: $_isConnecting, connected: $_isConnected)',
      );
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
      debugPrint('Error initializing: $e');
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
    final now = DateTime.now();
    debugPrint(
      'Connected successfully at ${now.toIso8601String()}',
    );
    _isConnected = true;
    _isConnecting = false;
    _retryCount = 0;
    _consecutiveFailures = 0;
    _pingFailures = 0; // Reset ping failure count on successful connection

    // Reset message tracking to prevent immediate idle detection
    _lastMessageTime = now;
    debugPrint(
      '🏓 WebSocket: Reset idle timer - will start pinging after 15 minutes if no activity',
    );

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
    debugPrint('Connection error: $error');

    // If we're in a graceful disconnect, ignore the error - it's expected
    if (_isGracefulDisconnect) {
      debugPrint(
        '🔌 WebSocket: Ignoring error during graceful disconnect - this is expected',
      );
      return;
    }

    _consecutiveFailures++;
    _stopHealthMonitoring();

    // Handle specific error types as suggested in debugging guide
    if (error.toString().contains('EOFException') ||
        error.toString().contains('Connection reset') ||
        error.toString().contains('mobile_network_behavior') ||
        error.toString().contains('Software caused connection abort') ||
        error.toString().contains('errno = 103')) {
      debugPrint(
        '🔌 WebSocket: Detected mobile network behavior - scheduling faster reconnect',
      );
      _handleMobileNetworkFailure();
    } else {
      _handleConnectionFailure();
    }
  }

  /// Enhanced disconnect handler
  void _onDisconnect(StompFrame frame) {
    debugPrint('🔌 WebSocket: Disconnected');
    _isConnected = false;
    _isConnecting = false;
    _stopHealthMonitoring();
    _safeNotifyListeners();
    _notifyConnectionListeners(false);

    // Only attempt to reconnect if this wasn't a graceful manual disconnect
    if (!_isGracefulDisconnect) {
      debugPrint('Unexpected disconnect - scheduling reconnect');
      _scheduleReconnectWithBackoff();
    } else {
      debugPrint('🔌 WebSocket: Graceful disconnect - no auto-reconnect');
      _isGracefulDisconnect = false; // Reset flag
    }
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
      debugPrint('Max retry attempts reached');
    }
  }

  /// Handle mobile network behavior failures with faster reconnection
  void _handleMobileNetworkFailure() {
    _isConnected = false;
    _isConnecting = false;
    _safeNotifyListeners();
    _notifyConnectionListeners(false);

    // Faster reconnection for mobile network issues (as suggested in debugging guide)
    _retryCount++;
    if (_retryCount <= _maxRetries) {
      debugPrint(
        '🔌 WebSocket: Mobile network failure - attempting fast reconnect in 1s (attempt $_retryCount/$_maxRetries)',
      );
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 1), () {
        if (!_isConnected && !_isConnecting) {
          initialize();
        }
      });
    } else {
      debugPrint(
        'Max retry attempts reached for mobile network failures',
      );
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
      'Scheduling reconnect attempt $_retryCount/$_maxRetries in ${finalDelay.inSeconds}s',
    );

    // Cancel any existing timer
    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(finalDelay, () {
      if (!_isConnected && !_isConnecting) {
        initialize();
      }
    });
  }

  /// Start health monitoring with industry-standard intervals
  void _startHealthMonitoring() {
    _stopHealthMonitoring(); // Clear any existing timer

    // Use 60-second intervals for health checks (industry standard)
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _performHealthCheck();
    });

    _lastHealthCheck = DateTime.now();
    debugPrint('💓 WebSocket: Health monitoring started (60s intervals)');
  }

  /// Stop health monitoring
  void _stopHealthMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    debugPrint('💓 WebSocket: Health monitoring stopped');
  }

  /// Perform health check with progressive ping intervals
  void _performHealthCheck() {
    if (!_isConnected || _stompClient == null) return;

    final now = DateTime.now();
    _lastHealthCheck = now;

    // Check if we've received any messages recently
    final timeSinceLastMessage =
        _lastMessageTime != null
            ? now.difference(_lastMessageTime!)
            : const Duration(hours: 1);

    // Progressive ping logic based on industry standards
    bool shouldPing = false;
    String reason = '';

    if (timeSinceLastMessage >= _longIdleThreshold) {
      // Extended idle (30+ minutes): ping every 10 minutes
      final timeSinceLastPing =
          _lastSuccessfulPing != null
              ? now.difference(_lastSuccessfulPing!)
              : _longPingInterval;

      if (timeSinceLastPing >= _longPingInterval) {
        shouldPing = true;
        reason =
            'Extended idle (${timeSinceLastMessage.inMinutes}min) - ping every 10min';
      }
    } else if (timeSinceLastMessage >= _initialIdleThreshold) {
      // Initial idle (15+ minutes): ping every 5 minutes
      final timeSinceLastPing =
          _lastSuccessfulPing != null
              ? now.difference(_lastSuccessfulPing!)
              : _shortPingInterval;

      if (timeSinceLastPing >= _shortPingInterval) {
        shouldPing = true;
        reason =
            'Initial idle (${timeSinceLastMessage.inMinutes}min) - ping every 5min';
      }
    }

    if (shouldPing) {
      debugPrint('🏓 WebSocket: $reason');
      debugPrint(
        '🏓 WebSocket: Connection stable for ${now.difference(_lastMessageTime!).inMinutes} minutes',
      );
      _sendPing();
    }

    // Only log detailed status every 5 minutes to reduce log spam
    if (_lastHealthCheck == null ||
        now.difference(_lastHealthCheck!).inMinutes >= 5) {
      debugPrint(
        '💓 WebSocket: Health check - Connected: $_isConnected, Idle: ${timeSinceLastMessage.inMinutes}min, Messages sent: $_messagesSent, received: $_messagesReceived, Ping failures: $_pingFailures',
      );
    }
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

      _lastSuccessfulPing = DateTime.now();
      debugPrint('🏓 WebSocket: Sent ping message');
    } catch (e) {
      debugPrint('Error sending ping: $e');
      _pingFailures++;
    }
  }

  /// Subscribe to a topic with a message handler
  void subscribe(String topic, WebSocketMessageHandler handler) {
    debugPrint('WebSocket: Subscribing to $topic');

    // Add handler to subscriptions (prevent duplicates)
    if (!_subscriptions.containsKey(topic)) {
      _subscriptions[topic] = [];
    }

    // Check if this handler is already subscribed to prevent duplicates
    if (!_subscriptions[topic]!.contains(handler)) {
      _subscriptions[topic]!.add(handler);
      debugPrint(
        'Added new handler for $topic (total: ${_subscriptions[topic]!.length})',
      );
    } else {
      debugPrint(
        'Handler already exists for $topic, skipping duplicate',
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
          'WebSocket: Already subscribed to $topic, reusing existing subscription',
        );
      }
    }
  }

  /// Unsubscribe from a topic
  void unsubscribe(String topic, WebSocketMessageHandler handler) {
    debugPrint('WebSocket: Unsubscribing from $topic');

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
      debugPrint('Cannot subscribe to $topic - not connected');
      return;
    }

    try {
      _stompClient!.subscribe(
        destination: topic,
        callback: (StompFrame frame) {
          debugPrint('### WebSocket: STOMP frame received for $topic ###');
          if (frame.body != null) {
            debugPrint('### WebSocket: Frame has body: ${frame.body!} ###');
            _handleMessage(topic, frame.body!);
          } else {
            debugPrint('### WebSocket: Frame has NO BODY for $topic ###');
          }
        },
      );

      debugPrint('Subscribed to $topic');
    } catch (e) {
      debugPrint('Failed to subscribe to $topic: $e');
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

      debugPrint('*** WebSocket: RECEIVED MESSAGE for topic: $topic ***');
      debugPrint('*** WebSocket: Message body: $body ***');
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
          debugPrint('Error in debug message listener: $e');
        }
      }

      // Notify all handlers for this topic
      if (_subscriptions.containsKey(topic)) {
        for (var handler in _subscriptions[topic]!) {
          try {
            handler(jsonData);
          } catch (e) {
            debugPrint('Error in message handler for $topic: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing message from $topic: $e');
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
      debugPrint('Error notifying new connection listener: $e');
    }
  }

  /// Remove connection status listener
  void removeConnectionListener(ConnectionStatusHandler listener) {
    _connectionListeners.remove(listener);
  }

  /// Add debug message listener (for test screen)
  void addDebugMessageListener(WebSocketMessageHandler listener) {
    _debugMessageListeners.add(listener);
    debugPrint('Added debug message listener');
  }

  /// Remove debug message listener
  void removeDebugMessageListener(WebSocketMessageHandler listener) {
    _debugMessageListeners.remove(listener);
    debugPrint('Removed debug message listener');
  }

  /// Notify all connection listeners
  void _notifyConnectionListeners(bool isConnected) {
    for (var listener in _connectionListeners) {
      try {
        listener(isConnected);
      } catch (e) {
        debugPrint('Error in connection listener: $e');
      }
    }
  }

  /// Enhanced message sending with metrics
  void sendMessage(String destination, Map<String, dynamic> message) {
    if (!_isConnected || _stompClient == null) {
      debugPrint('Cannot send message - not connected');
      return;
    }

    try {
      final messageBody = jsonEncode(message);
      _stompClient!.send(destination: destination, body: messageBody);

      _messagesSent++;
      debugPrint('📤 WebSocket: Sent message to $destination: $messageBody');
    } catch (e) {
      debugPrint('Error sending message: $e');
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
    _isGracefulDisconnect = false; // Reset flag
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

  /// Graceful disconnect without auto-reconnect (for Activity lifecycle management)
  void disconnectWithoutReconnect() {
    debugPrint(
      '🔌 WebSocket: Graceful disconnect without auto-reconnect (current state: connected=$_isConnected, connecting=$_isConnecting)',
    );

    // Set flag to prevent auto-reconnect in _onDisconnect callback
    _isGracefulDisconnect = true;

    // Stop all timers
    _stopHealthMonitoring();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Gracefully disconnect - this will trigger _onDisconnect but with our flag set
    if (_stompClient != null) {
      debugPrint('🔌 WebSocket: Deactivating StompClient');
      _stompClient!.deactivate();
      _stompClient = null;
      debugPrint('🔌 WebSocket: StompClient deactivated and set to null');
    } else {
      debugPrint('🔌 WebSocket: No StompClient to deactivate');
    }

    // Update state but keep subscriptions and listeners for reconnection
    _isConnected = false;
    _isConnecting = false;
    // Don't reset _retryCount or _subscriptions - we want to reconnect exactly as we were

    debugPrint(
      '🔌 WebSocket: State updated (connected=$_isConnected, connecting=$_isConnecting)',
    );
    _safeNotifyListeners();
    _notifyConnectionListeners(false);
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
    debugPrint('Force reconnecting...');

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
        debugPrint('Error parsing DM message: $e');
      }
    });

    // Subscribe to new messages for this user (separated from comments/reactions)
    // The backend will broadcast to this topic for all families the user belongs to
    subscribe('/user/$userId/messages', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('Error parsing new message: $e');
      }
    });

    // Subscribe to test messages
    subscribe('/topic/test', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('Error parsing test message: $e');
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
        debugPrint('Error parsing DM message: $e');
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
          debugPrint('Error parsing family message: $e');
        }
      });
    }

    // Subscribe to test messages
    subscribe('/topic/test', (data) {
      try {
        final message = Message.fromJson(data);
        listener(message);
      } catch (e) {
        debugPrint('Error parsing test message: $e');
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
        debugPrint('Error parsing test message: $e');
      }
    });
  }

  /// Subscribe to family messages for a specific family
  void subscribeToFamilyMessages(int familyId, MessageHandler handler) {
    final topic = '/family/$familyId';
    debugPrint('WebSocket: Subscribing to family messages: $topic');
    subscribe(topic, (data) {
      try {
        final message = Message.fromJson(data);
        handler(message);
      } catch (e) {
        debugPrint('Error parsing family message: $e');
      }
    });
  }

  /// Subscribe to DM messages for a specific user
  void subscribeToDMMessages(int userId, MessageHandler handler) {
    final topic = '/topic/dm/$userId';
    debugPrint('WebSocket: Subscribing to DM messages: $topic');
    subscribe(topic, (data) {
      try {
        final message = Message.fromJson(data);
        handler(message);
      } catch (e) {
        debugPrint('Error parsing DM message: $e');
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
