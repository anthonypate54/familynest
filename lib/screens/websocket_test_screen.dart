import 'package:familynest/models/dm_message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import '../services/api_service.dart';
import '../config/app_config.dart';

class WebSocketTestScreen extends StatefulWidget {
  const WebSocketTestScreen({Key? key}) : super(key: key);

  @override
  State<WebSocketTestScreen> createState() => _WebSocketTestScreenState();
}

class _WebSocketTestScreenState extends State<WebSocketTestScreen> {
  StompClient? stompClient;
  List<DMMessage> messages = [];
  int? userId;

  @override
  void initState() {
    super.initState();
    _initUserAndConnect();
  }

  Future<void> _initUserAndConnect() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final user =
        await apiService.getCurrentUser(); // This is a Map<String, dynamic>?
    if (user != null && user['userId'] != null) {
      setState(() {
        userId = user['userId'] as int;
        ; // or as String, depending on your backend
      });
      // Now you can activate the stomp client and subscribe
      final baseUrl = AppConfig().baseUrl;
      final wsUrl = '$baseUrl/ws';
      debugPrint('Connecting to WebSocket at: $wsUrl');

      stompClient = StompClient(
        config: StompConfig.SockJS(
          url: wsUrl,
          onConnect: onConnect,
          onWebSocketError: (dynamic error) => debugPrint(error.toString()),
        ),
      );
      stompClient!.activate();
    } else {
      debugPrint('User not found or missing id');
    }
  }

  void onConnect(StompFrame frame) {
    if (userId == null) return;
    stompClient!.subscribe(
      destination: '/topic/dm/$userId',
      callback: (StompFrame frame) {
        if (frame.body != null) {
          try {
            debugPrint('Raw WebSocket payload: ${frame.body}');
            final jsonData = jsonDecode(frame.body!);
            debugPrint('Parsed JSON data: $jsonData');
            final dm = DMMessage.fromJson(jsonData);
            setState(() {
              messages.add(dm);
            });
            debugPrint('Successfully parsed DM message: $dm');
          } catch (e, stackTrace) {
            debugPrint('❌ Error parsing WebSocket message: $e');
            debugPrint('Stack trace: $stackTrace');
            debugPrint('Raw message body: ${frame.body}');
          }
        }
      },
    );
  }

  @override
  void dispose() {
    stompClient?.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebSocket DM Test')),
      body: ListView.builder(
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final msg = messages[index];
          return ListTile(
            title: Text(msg.content),
            subtitle: Text(
              msg.toString().isEmpty ? 'No Messages' : msg.toString(),
            ),
          );
        },
      ),
    );
  }
}
