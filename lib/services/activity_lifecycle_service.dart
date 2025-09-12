import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'websocket_service.dart';

/// Service to coordinate Activity lifecycle events with WebSocket connections
/// This prevents WebSocket disruption during file picker operations
class ActivityLifecycleService {
  static final ActivityLifecycleService _instance =
      ActivityLifecycleService._internal();
  factory ActivityLifecycleService() => _instance;
  ActivityLifecycleService._internal();

  static const MethodChannel _lifecycleChannel = MethodChannel(
    'com.anthony.familynest/lifecycle',
  );

  bool _isInitialized = false;
  bool _isFilePickerActive = false;
  bool _wasWebSocketConnected = false;

  /// Initialize the lifecycle service
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔌 ActivityLifecycleService: Initializing');

    _lifecycleChannel.setMethodCallHandler(_handleLifecycleEvent);
    _isInitialized = true;

    debugPrint('Initialized');
  }

  /// Handle lifecycle events from Android MainActivity
  Future<void> _handleLifecycleEvent(MethodCall call) async {
    debugPrint('🔌 ActivityLifecycleService: Received ${call.method}');

    switch (call.method) {
      case 'onFilePickerStarting':
        await _handleFilePickerStarting();
        break;

      case 'onFilePickerCompleted':
        await _handleFilePickerCompleted();
        break;

      case 'onActivityPausing':
        await _handleActivityPausing();
        break;

      case 'onActivityResuming':
        await _handleActivityResuming();
        break;

      case 'onActivityStopping':
        await _handleActivityStopping();
        break;

      case 'onActivityStarting':
        await _handleActivityStarting();
        break;

      default:
        debugPrint(
          '🔌 ActivityLifecycleService: Unknown lifecycle event: ${call.method}',
        );
    }
  }

  /// Handle file picker starting - prepare WebSocket for potential disruption
  Future<void> _handleFilePickerStarting() async {
    debugPrint('🔌 ActivityLifecycleService: File picker starting');
    _isFilePickerActive = true;

    // Remember if WebSocket was connected
    _wasWebSocketConnected = WebSocketService().isConnected;

    if (_wasWebSocketConnected) {
      debugPrint(
        '🔌 ActivityLifecycleService: Gracefully disconnecting WebSocket before file picker',
      );
      // Proactively disconnect to prevent EOFException during Activity transition
      WebSocketService().disconnect();

      // Small delay to ensure disconnect completes before Activity transition
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('🔌 ActivityLifecycleService: WebSocket disconnect completed');
    }
  }

  /// Handle file picker completed - restore WebSocket if needed
  Future<void> _handleFilePickerCompleted() async {
    debugPrint('🔌 ActivityLifecycleService: File picker completed');
    _isFilePickerActive = false;

    // Small delay to let Activity fully resume
    await Future.delayed(const Duration(milliseconds: 500));

    if (_wasWebSocketConnected && !WebSocketService().isConnected) {
      debugPrint(
        '🔌 ActivityLifecycleService: Reconnecting WebSocket after file picker',
      );
      await WebSocketService().initialize();
    }
  }

  /// Handle Activity pausing
  Future<void> _handleActivityPausing() async {
    debugPrint('🔌 ActivityLifecycleService: Activity pausing');

    if (_isFilePickerActive) {
      debugPrint(
        '🔌 ActivityLifecycleService: Activity pausing due to file picker - preserving WebSocket state',
      );
      // Don't force disconnect - let WebSocket handle gracefully
    }
  }

  /// Handle Activity resuming
  Future<void> _handleActivityResuming() async {
    debugPrint('🔌 ActivityLifecycleService: Activity resuming');

    if (_isFilePickerActive) {
      debugPrint(
        '🔌 ActivityLifecycleService: Activity resuming from file picker',
      );
      // Will be handled in onFilePickerCompleted
    } else {
      // Normal app resume - ensure WebSocket is connected
      if (!WebSocketService().isConnected) {
        debugPrint(
          '🔌 ActivityLifecycleService: Reconnecting WebSocket on app resume',
        );
        await Future.delayed(const Duration(milliseconds: 200));
        await WebSocketService().initialize();
      }
    }
  }

  /// Handle Activity stopping
  Future<void> _handleActivityStopping() async {
    debugPrint('🔌 ActivityLifecycleService: Activity stopping');
    // WebSocket should handle this gracefully through its own mechanisms
  }

  /// Handle Activity starting
  Future<void> _handleActivityStarting() async {
    debugPrint('🔌 ActivityLifecycleService: Activity starting');
    // WebSocket reconnection will be handled in onResume
  }

  /// Check if file picker is currently active
  bool get isFilePickerActive => _isFilePickerActive;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
