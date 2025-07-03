import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
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
    _safeNotifyListeners();

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

  /// Safe method to call notifyListeners outside of build phase
  void _safeNotifyListeners() {
    // Use Future.microtask to defer notifyListeners to avoid build phase issues
    Future.microtask(() {
      notifyListeners();
    });
  }

  /// Handle successful connection
  void _onConnect(StompFrame frame) {
    debugPrint('✅ WebSocket: Connected successfully');
    _isConnected = true;
    _isConnecting = false;
    _retryCount = 0;
    _safeNotifyListeners();
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
    _safeNotifyListeners();
    _notifyConnectionListeners(false);

    // Attempt to reconnect
    _scheduleReconnect();
  }

  /// Handle connection failure
  void _handleConnectionFailure() {
    _isConnected = false;
    _isConnecting = false;
    _safeNotifyListeners();
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
