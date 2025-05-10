# FamilyNest App Configuration

This directory contains configuration classes for managing environment-specific settings in the FamilyNest application.

## AppConfig

The `AppConfig` class provides a central place to manage environment-specific configurations, such as API URLs, feature flags, and other settings that change between development, staging, and production environments.

### Usage

#### Basic Usage

```dart
import 'package:familynest/config/app_config.dart';

// Access the configuration (singleton)
final config = AppConfig();

// Get the base URL for the current environment
String apiUrl = config.baseUrl;
```

#### Setting the Environment

The default environment is `development`. To change the environment:

```dart
config.setEnvironment(Environment.production);
```

#### Setting a Custom Base URL

For local development or testing, you can override the default URL:

```dart
config.setCustomBaseUrl("http://192.168.1.100:8080");
```

### Build Configuration

You can configure the app at build time using `--dart-define`:

```bash
# For production builds
flutter build apk --dart-define=ENVIRONMENT=production

# For staging builds
flutter build apk --dart-define=ENVIRONMENT=staging

# For development with a custom API
flutter build apk --dart-define=USE_LOCAL_API=true --dart-define=API_URL=http://192.168.1.100:8080
```

### Default URLs

- **Development**: 
  - Web: `http://localhost:8080`
  - Android: `http://10.0.2.2:8080`
  - iOS/Others: `http://localhost:8080`

- **Staging**: `https://staging-api.familynest.example.com`

- **Production**: `https://api.familynest.example.com`

Remember to update these URLs with your actual API endpoints before deploying to production. 