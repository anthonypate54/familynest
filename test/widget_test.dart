import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:familynest/main.dart';
import 'package:familynest/services/api_service.dart';
import 'package:familynest/screens/login_screen.dart';
import 'package:familynest/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'widget_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoginScreen Tests', () {
    late MockClient mockClient;
    late ApiService apiService;
    late String baseUrl;

    setUp(() async {
      mockClient = MockClient();
      SharedPreferences.setMockInitialValues({});
      apiService = ApiService(client: mockClient);
      baseUrl =
          Platform.isAndroid ? "http://10.0.2.2:8080" : "http://localhost:8080";

      // Mock the test connection endpoint to always succeed
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      await apiService.initialize();
    });

    testWidgets('LoginScreen shows error on failed connection test', (
      WidgetTester tester,
    ) async {
      // Reset the mock to ensure clean state
      reset(mockClient);

      // Set up mock token storage
      SharedPreferences.setMockInitialValues({});

      // Mock failed connection test
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Connection failed', 500));

      // Mock login endpoint to throw the expected error
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/login'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async =>
            http.Response('Connection test failed with status: 500', 500),
      );

      // Create a new ApiService instance for this test
      final testApiService = ApiService(client: mockClient);

      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(apiService: testApiService)),
      );

      // Wait for initialization to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Try to log in to trigger the error
      await tester.enterText(
        find.byKey(const Key('usernameField')),
        'testuser',
      );
      await tester.enterText(
        find.byKey(const Key('passwordField')),
        'password',
      );
      await tester.tap(find.byKey(const Key('loginButton')));

      // Wait for the error to be handled and dialog to appear
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // First verify the dialog exists
      expect(find.byType(AlertDialog), findsOneWidget);

      // Then verify its contents
      expect(find.text('Login Failed'), findsOneWidget);
      expect(find.textContaining('Connection test failed'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('LoginScreen navigates to ProfileScreen on successful login', (
      WidgetTester tester,
    ) async {
      // Mock successful connection test
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock successful login
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/login'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"token": "mock_token", "userId": 1, "role": "USER"}',
          200,
        ),
      );

      // Mock getCurrentUser response
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/current'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"userId": 1, "role": "USER"}', 200),
      );

      // Mock getUserById response
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/1'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"username": "testuser", "firstName": "Test", "lastName": "User", "role": "USER"}',
          200,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(apiService: apiService)),
      );

      // Wait for async operations to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Find and enter text in the username field
      final usernameField = find.byKey(const Key('usernameField'));
      expect(usernameField, findsOneWidget);
      await tester.enterText(usernameField, 'testuser');

      // Find and enter text in the password field
      final passwordField = find.byKey(const Key('passwordField'));
      expect(passwordField, findsOneWidget);
      await tester.enterText(passwordField, 'password');

      // Find and tap the login button
      final loginButton = find.byKey(const Key('loginButton'));
      expect(loginButton, findsOneWidget);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      // Verify navigation to ProfileScreen
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('LoginScreen shows error dialog on failed login', (
      WidgetTester tester,
    ) async {
      // Mock successful connection test
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock failed login with proper error response
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/login'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"error": "Invalid credentials"}',
          401,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(apiService: apiService)),
      );

      // Wait for async operations to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Enter credentials and login
      await tester.enterText(
        find.byKey(const Key('usernameField')),
        'testuser',
      );
      await tester.enterText(
        find.byKey(const Key('passwordField')),
        'wrongpassword',
      );
      await tester.tap(find.byKey(const Key('loginButton')));

      // Wait for the dialog to appear
      await tester.pumpAndSettle();

      // Verify error dialog is shown with correct content
      expect(find.text('Login Failed'), findsOneWidget);
      expect(
        find.text(
          'Error logging in: Exception: Failed to login: statusCode=401, body={"error": "Invalid credentials"}',
        ),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);
    });
  });

  group('ApiService Tests', () {
    late MockClient mockClient;
    late ApiService apiService;
    late String baseUrl;

    setUp(() async {
      mockClient = MockClient();
      SharedPreferences.setMockInitialValues({});
      apiService = ApiService(client: mockClient);
      baseUrl =
          Platform.isAndroid ? "http://10.0.2.2:8080" : "http://localhost:8080";

      // Mock the test connection endpoint to always succeed
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      await apiService.initialize();
    });

    test('testConnection succeeds on successful connection', () async {
      // Mock successful connection test with proper response body
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Since testConnection is void, we just verify it completes without throwing
      await expectLater(apiService.testConnection(), completes);
    });

    test('testConnection handles failed connection', () async {
      // Reset the mock to ensure clean state
      reset(mockClient);

      // Set up mock token storage
      SharedPreferences.setMockInitialValues({});

      // Create a new ApiService instance for this test
      final testApiService = ApiService(client: mockClient);

      // Mock failed connection test
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Connection failed', 500));

      // Verify that testConnection completes without throwing
      await expectLater(testApiService.testConnection(), completes);
    });

    test('loginUser returns user data on successful login', () async {
      // Reset the mock to ensure clean state
      reset(mockClient);

      // Set up mock token storage
      SharedPreferences.setMockInitialValues({});

      // Mock successful test connection
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock successful login
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/login'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"token": "mock_token", "userId": 1, "role": "ADMIN"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      // Create a new ApiService instance for this test
      final testApiService = ApiService(client: mockClient);
      await testApiService.initialize();

      // Verify token is initially null
      expect(
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.getString('auth_token'),
        ),
        isNull,
      );

      final result = await testApiService.loginUser('testuser', 'password');

      // Verify the result
      expect(result['userId'], 1);
      expect(result['token'], 'mock_token');
      expect(result['role'], 'ADMIN');

      // Verify token was saved
      expect(
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.getString('auth_token'),
        ),
        'mock_token',
      );
    });

    test('loginUser throws exception on failed login', () async {
      // Mock failed login
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/login'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => http.Response('Invalid credentials', 401));

      expect(
        () => apiService.loginUser('testuser', 'wrongpassword'),
        throwsException,
      );
    });
  });
}
