// File used to generate mocks for testing
// Run this with: flutter pub run build_runner build --delete-conflicting-outputs

import 'package:familynest/services/api_service.dart';
import 'package:mockito/annotations.dart';

// This will generate mocks for the ApiService
@GenerateMocks([ApiService])
void main() {}
