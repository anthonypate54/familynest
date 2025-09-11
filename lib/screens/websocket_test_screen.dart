// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../models/message.dart';
import 'dart:convert';

class WebSocketTestScreen extends StatefulWidget {
  const WebSocketTestScreen({super.key});

  @override
  WebSocketTestScreenState createState() => WebSocketTestScreenState();
}

class WebSocketTestScreenState extends State<WebSocketTestScreen> {
  List<Message> _receivedMessages = [];
  List<Map<String, dynamic>> _receivedRawMessages = [];
  bool _isConnected = false;
  int? _currentUserId;
  int? _currentFamilyId;
  int _subscribedFamiliesCount = 0;
  WebSocketService? _webSocketService;
  WebSocketMessageHandler? _debugMessageHandler;

  @override
  void initState() {
    super.initState();
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final currentUser = await apiService.getCurrentUser();

      if (currentUser != null && mounted) {
        final userId = currentUser['userId'] as int;

        // Get ALL families the user belongs to instead of just primary family
        final userFamilies = await apiService.getJoinedFamilies(userId);

        setState(() {
          _currentUserId = userId;
          // Show the first family ID for display, but we'll subscribe to all
          _currentFamilyId =
              userFamilies.isNotEmpty
                  ? userFamilies.first['familyId'] as int?
                  : null;
          _subscribedFamiliesCount = userFamilies.length;
        });

        debugPrint('🔍 WebSocket Test: User ID: $userId');
        debugPrint(
          '🔍 WebSocket Test: User belongs to ${userFamilies.length} families:',
        );
        for (var family in userFamilies) {
          debugPrint(
            '  - Family ${family['familyId']}: ${family['familyName']}',
          );
        }

        // Now initialize WebSocket with all families
        _initializeWebSocket(userFamilies);
      }
    } catch (e) {
      debugPrint('❌ Error getting current user: $e');
      _initializeWebSocket(
        [],
      ); // Still initialize WebSocket even if user fetch fails
    }
  }

  Future<void> _initializeWebSocket(List<Map<String, dynamic>> families) async {
    if (_webSocketService == null) return;

    // Get the current connection status from the shared service
    setState(() {
      _isConnected = _webSocketService!.isConnected;
    });

    // Add connection status listener to track changes
    _webSocketService!.addConnectionListener((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });

    // Don't re-initialize! Just use the existing service
    // The WebSocket service should already be initialized by the main app
    debugPrint(
      '🔍 WS TEST: Using existing WebSocket service (connected: $_isConnected)',
    );

    // Use the new simplified approach - single method that handles all message types
    if (_currentUserId != null) {
      // Use the new addMessageListenerForUser method which handles both DM and family messages
      _webSocketService!.addMessageListenerForUser(_currentUserId!, (message) {
        debugPrint(
          '🔍 WS TEST: Received message via new architecture: ${message.toJson()}',
        );
        if (mounted) {
          setState(() {
            _receivedMessages.add(message);
          });
        }
      });

      // Also add a debug message listener to capture all raw WebSocket traffic
      _debugMessageHandler = (data) {
        debugPrint('🔍 WS TEST: Raw WebSocket data: $data');
        if (mounted) {
          setState(() {
            _receivedRawMessages.add(data);
          });
        }
      };
      _webSocketService!.addDebugMessageListener(_debugMessageHandler!);

      debugPrint(
        '🔍 WS TEST: Subscribed using NEW ARCHITECTURE for user $_currentUserId',
      );
      debugPrint(
        '🔍 WS TEST: User belongs to ${families.length} families, using single user-specific subscription',
      );
    }

    debugPrint(
      '🔍 WS TEST: WebSocket Test Screen initialized with NEW IMPROVED architecture',
    );
    debugPrint(
      '🔍 WS TEST: Connection status from shared service: $_isConnected',
    );
  }

  @override
  void dispose() {
    // Clean up debug message listener
    if (_debugMessageHandler != null && _webSocketService != null) {
      _webSocketService!.removeDebugMessageListener(_debugMessageHandler!);
    }
    super.dispose();
  }

  Widget _buildSimpleMessageCard(Message message) {
    final timestamp = message.createdAt ?? DateTime.now();
    final timeString =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple header
            Row(
              children: [
                Text(
                  '📨 Message (ID: ${message.id})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  timeString,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Message details
            Text(
              'From: ${message.senderUserName ?? message.userName ?? "Unknown"}',
            ),
            Text(
              'Content: ${message.content.isNotEmpty ? message.content : "No content"}',
            ),
            if (message.senderId != null)
              Text('Sender ID: ${message.senderId}'),

            const SizedBox(height: 8),

            // Pretty formatted JSON
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(message.toJson()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawMessageCard(Map<String, dynamic> rawMessage) {
    final timestamp = DateTime.now();
    final timeString =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple header
            Row(
              children: [
                Text(
                  '🔍 Raw WebSocket Data',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Spacer(),
                Text(
                  timeString,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Show topic and timestamp if available
            if (rawMessage['topic'] != null)
              Text(
                'Topic: ${rawMessage['topic']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (rawMessage['timestamp'] != null)
              Text('Timestamp: ${rawMessage['timestamp']}'),

            const SizedBox(height: 8),

            // Pretty formatted JSON
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(rawMessage),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isConnected
                    ? 'WebSocket: Connected'
                    : 'WebSocket: Disconnected',
                style: const TextStyle(fontSize: 16),
              ),
              if (_currentUserId != null)
                Text(
                  'User: $_currentUserId${_currentFamilyId != null ? ', Family: $_currentFamilyId' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          backgroundColor: _isConnected ? Colors.green : Colors.red,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                setState(() {
                  _receivedMessages.clear();
                  _receivedRawMessages.clear();
                });
              },
              tooltip: 'Clear All Messages',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Parsed Messages'),
              Tab(text: 'Raw WebSocket Data'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Connection Status Card
            Card(
              margin: const EdgeInsets.all(16),
              color: _isConnected ? Colors.green[50] : Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          size: 32,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected
                              ? 'WebSocket Connected ✅'
                              : 'WebSocket Disconnected ❌',
                          style: TextStyle(
                            color: _isConnected ? Colors.green : Colors.red,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('User ID: ${_currentUserId ?? "Loading..."}'),
                    Text('Family ID: ${_currentFamilyId ?? "None"}'),
                    Text('Subscribed Families: $_subscribedFamiliesCount'),
                    const Text(
                      'Using NEW WebSocket Architecture (Single User Subscription)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  // Parsed Messages Tab
                  Column(
                    children: [
                      // Messages Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              'Parsed Messages (${_receivedMessages.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_receivedMessages.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _receivedMessages.clear();
                                  });
                                },
                                icon: const Icon(Icons.clear_all),
                                label: const Text('Clear'),
                              ),
                          ],
                        ),
                      ),

                      // Messages List
                      Expanded(
                        child:
                            _receivedMessages.isEmpty
                                ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.message_outlined,
                                        size: 64,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No parsed messages received yet',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Post a message to see real-time updates!',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : ListView.builder(
                                  reverse: true,
                                  itemCount: _receivedMessages.length,
                                  itemBuilder: (context, index) {
                                    final reverseIndex =
                                        _receivedMessages.length - 1 - index;
                                    return _buildSimpleMessageCard(
                                      _receivedMessages[reverseIndex],
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),

                  // Raw WebSocket Data Tab
                  Column(
                    children: [
                      // Raw Messages Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              'Raw WebSocket Data (${_receivedRawMessages.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_receivedRawMessages.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _receivedRawMessages.clear();
                                  });
                                },
                                icon: const Icon(Icons.clear_all),
                                label: const Text('Clear'),
                              ),
                          ],
                        ),
                      ),

                      // Raw Messages List
                      Expanded(
                        child:
                            _receivedRawMessages.isEmpty
                                ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.data_object,
                                        size: 64,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No raw WebSocket data captured yet',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'All WebSocket traffic will appear here',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : ListView.builder(
                                  reverse: true,
                                  itemCount: _receivedRawMessages.length,
                                  itemBuilder: (context, index) {
                                    final reverseIndex =
                                        _receivedRawMessages.length - 1 - index;
                                    return _buildRawMessageCard(
                                      _receivedRawMessages[reverseIndex],
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
