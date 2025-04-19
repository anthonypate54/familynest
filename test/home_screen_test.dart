import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:familynest/services/api_service.dart';
import 'package:familynest/screens/home_screen.dart';
import 'package:familynest/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'home_screen_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeScreen Tests', () {
    late MockClient mockClient;
    late ApiService apiService;
    late String baseUrl;

    setUp(() async {
      mockClient = MockClient();
      SharedPreferences.setMockInitialValues({'auth_token': 'mock_token'});
      apiService = ApiService(client: mockClient);
      baseUrl =
          Platform.isAndroid ? "http://10.0.2.2:8080" : "http://localhost:8080";

      // Mock the test connection endpoint
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      await apiService.initialize();
    });

    testWidgets('HomeScreen displays message if user has no family', (
      WidgetTester tester,
    ) async {
      // Mock test endpoint
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock failed message load (user has no family)
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/2/messages'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"error": "User has no familyId"}', 400),
      );

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(apiService: apiService, userId: 2)),
      );

      // Wait for async operations to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Verify UI
      expect(find.text('Failed to load messages'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'HomeScreen displays "No messages yet" if user has a family with no messages',
      (WidgetTester tester) async {
        // Mock test endpoint
        when(
          mockClient.get(
            Uri.parse('$baseUrl/api/users/test'),
            headers: anyNamed('headers'),
          ),
        ).thenAnswer((_) async => http.Response('Test successful', 200));

        // Mock empty message list (user has a family but no messages)
        when(
          mockClient.get(
            Uri.parse('$baseUrl/api/users/2/messages'),
            headers: anyNamed('headers'),
          ),
        ).thenAnswer((_) async => http.Response('[]', 200));

        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(apiService: apiService, userId: 2)),
        );

        // Wait for async operations to complete
        await tester.pump(Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Verify UI
        expect(find.text('No messages yet'), findsOneWidget);
      },
    );

    testWidgets('HomeScreen allows posting messages if user has a family', (
      WidgetTester tester,
    ) async {
      // Mock test endpoint
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock empty message list initially
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/2/messages'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('[]', 200));

      // Mock successful message post
      when(
        mockClient.post(
          Uri.parse('$baseUrl/api/users/2/messages'),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => http.Response('', 201));

      // Mock updated message list after posting
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/2/messages'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"content":"Test message","senderUsername":"testuser","timestamp":"2025-04-17T12:00:00"}]',
          200,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(apiService: apiService, userId: 2)),
      );

      // Wait for async operations to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Enter a message and post
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify the message appears
      expect(find.text('Test message'), findsOneWidget);
      expect(
        find.text('From: testuser at 2025-04-17T12:00:00'),
        findsOneWidget,
      );
    });

    testWidgets('HomeScreen logout navigates to LoginScreen', (
      WidgetTester tester,
    ) async {
      // Mock test endpoint
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/test'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('Test successful', 200));

      // Mock empty message list
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/2/messages'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer((_) async => http.Response('[]', 200));

      // Mock getCurrentUser response
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/current'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"userId": 2, "role": "USER"}', 200),
      );

      // Mock getUserById response
      when(
        mockClient.get(
          Uri.parse('$baseUrl/api/users/2'),
          headers: anyNamed('headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"username": "testuser", "firstName": "Test", "lastName": "User", "role": "USER"}',
          200,
        ),
      );

      // Set initial token
      SharedPreferences.setMockInitialValues({'auth_token': 'mock_token'});
      await apiService.initialize();

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(apiService: apiService, userId: 2)),
      );

      // Wait for async operations to complete
      await tester.pump(Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Tap the profile button to navigate to ProfileScreen
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();

      // Tap the logout button
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      // Verify navigation to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
