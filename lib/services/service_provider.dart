import 'api_service.dart';
import 'invitation_service.dart';

/// Service provider for centralized access to all services in the app
class ServiceProvider {
  static final ServiceProvider _instance = ServiceProvider._internal();

  factory ServiceProvider() => _instance;

  ServiceProvider._internal();

  // Track initialization state
  bool _isInitialized = false;

  // Services
  late ApiService _apiService;
  late InvitationService _invitationService;

  // Getters for services to ensure they're initialized
  ApiService get apiService {
    _ensureInitialized();
    return _apiService;
  }

  InvitationService get invitationService {
    _ensureInitialized();
    return _invitationService;
  }

  // Initialize all services
  void initialize(ApiService apiService) {
    _apiService = apiService;
    _invitationService = InvitationService(apiService: apiService);
    _isInitialized = true;
  }

  // Ensure services are initialized before use
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception(
        'ServiceProvider not initialized. Call initialize() first.',
      );
    }
  }

  // Check if services are initialized without throwing
  bool get isInitialized => _isInitialized;

  // Reset all services (for logout)
  void reset() {
    // Add any cleanup logic here if needed
  }
}
