import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:familynest/dialogs/families_message_dialog.dart';
import 'package:familynest/dialogs/member_message_dialog.dart';
import 'package:familynest/services/api_service.dart';
import '../lib/test/message_preferences_test_data.dart';

// Import the generated mocks file
// This file is generated from generate_mocks.dart and copied to this location by the test script
import 'message_preferences_test.mocks.dart';

void main() {
  late MockApiService mockApiService;

  setUp(() {
    mockApiService = MockApiService();
  });

  group('FamiliesMessageDialog Tests', () {
    testWidgets('Should display families and their preferences', (
      WidgetTester tester,
    ) async {
      // Mock API responses
      final mockFamilies =
          MessagePreferencesTestData.getFamilyMessagePreferences();
      when(
        mockApiService.getMessagePreferences(1),
      ).thenAnswer((_) async => mockFamilies);

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => FamiliesMessageDialog(
                              apiService: mockApiService,
                              userId: 1,
                            ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
          ),
        ),
      );

      // Tap the button to open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog is shown with correct title
      expect(find.text('Families You Belong To'), findsOneWidget);

      // Verify each family is displayed
      for (final family in mockFamilies) {
        expect(find.text(family['familyName']), findsOneWidget);
      }

      // Verify we have checkboxes for each family
      expect(find.byType(CheckboxListTile), findsNWidgets(mockFamilies.length));
    });

    testWidgets('Should update family preference when checkbox is tapped', (
      WidgetTester tester,
    ) async {
      // Mock API responses
      final mockFamilies =
          MessagePreferencesTestData.getFamilyMessagePreferences();
      when(
        mockApiService.getMessagePreferences(1),
      ).thenAnswer((_) async => mockFamilies);

      // Mock the update response
      final mockUpdateResponse =
          MessagePreferencesTestData.updateFamilyMessagePreference(1, false);
      when(
        mockApiService.updateMessagePreference(1, 1, false),
      ).thenAnswer((_) async => mockUpdateResponse);

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => FamiliesMessageDialog(
                              apiService: mockApiService,
                              userId: 1,
                            ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
          ),
        ),
      );

      // Tap the button to open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Find the first checkbox (for Family 1) which should be checked (true)
      final firstCheckbox = find.byType(CheckboxListTile).first;

      // Tap the checkbox to toggle it
      await tester.tap(firstCheckbox);
      await tester.pumpAndSettle();

      // Verify the API was called with the correct parameters
      verify(mockApiService.updateMessagePreference(1, 1, false)).called(1);
    });

    testWidgets(
      'Should open member preferences dialog when settings icon is tapped',
      (WidgetTester tester) async {
        // Mock API responses
        final mockFamilies =
            MessagePreferencesTestData.getFamilyMessagePreferences();
        when(
          mockApiService.getMessagePreferences(1),
        ).thenAnswer((_) async => mockFamilies);

        // Mock member preferences
        final mockMemberPrefs =
            MessagePreferencesTestData.getMemberMessagePreferences();
        when(
          mockApiService.getMemberMessagePreferences(1),
        ).thenAnswer((_) async => mockMemberPrefs);

        when(mockApiService.getFamilyMembersByFamilyId(1, 1)).thenAnswer(
          (_) async =>
              mockMemberPrefs.where((m) => m['familyId'] == 1).toList(),
        );

        // Build the widget
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder:
                  (context) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder:
                              (context) => FamiliesMessageDialog(
                                apiService: mockApiService,
                                userId: 1,
                              ),
                        );
                      },
                      child: const Text('Open Dialog'),
                    ),
                  ),
            ),
          ),
        );

        // Tap the button to open the dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Find the settings icon for the first family and tap it
        final settingsIcon = find.byIcon(Icons.settings).first;
        await tester.tap(settingsIcon);
        await tester.pumpAndSettle();

        // Verify the member preferences dialog is shown
        expect(find.text('Test Family 1 Family Members'), findsOneWidget);
      },
    );
  });

  group('MemberMessageDialog Tests', () {
    testWidgets('Should display family members and their preferences', (
      WidgetTester tester,
    ) async {
      // Mock API responses
      final mockMembers =
          MessagePreferencesTestData.getMemberMessagePreferences()
              .where((m) => m['familyId'] == 1)
              .toList();

      when(
        mockApiService.getMemberMessagePreferences(1),
      ).thenAnswer((_) async => mockMembers);

      when(
        mockApiService.getFamilyMembersByFamilyId(1, 1),
      ).thenAnswer((_) async => mockMembers);

      // Create family data
      final family = {'familyId': 1, 'familyName': 'Test Family 1'};

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => MemberMessageDialog(
                              apiService: mockApiService,
                              userId: 1,
                              family: family,
                            ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
          ),
        ),
      );

      // Tap the button to open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog is shown with correct title
      expect(find.text('Test Family 1 Family Members'), findsOneWidget);

      // Verify first member is displayed (taking just the first one for simplicity)
      expect(find.text('Member 1'), findsOneWidget);

      // Verify we have checkboxes for each member
      expect(find.byType(CheckboxListTile), findsNWidgets(mockMembers.length));
    });

    testWidgets('Should update member preference when checkbox is tapped', (
      WidgetTester tester,
    ) async {
      // Mock API responses
      final mockMembers =
          MessagePreferencesTestData.getMemberMessagePreferences()
              .where((m) => m['familyId'] == 1)
              .toList();

      when(
        mockApiService.getMemberMessagePreferences(1),
      ).thenAnswer((_) async => mockMembers);

      when(
        mockApiService.getFamilyMembersByFamilyId(1, 1),
      ).thenAnswer((_) async => mockMembers);

      // Second member should be initially receiving messages (true)
      final memberUserId = mockMembers[1]['memberUserId'];

      // Mock the update response - toggle to false
      final mockUpdateResponse =
          MessagePreferencesTestData.updateMemberMessagePreference(
            1,
            memberUserId,
            false,
          );
      when(
        mockApiService.updateMemberMessagePreference(1, 1, memberUserId, false),
      ).thenAnswer((_) async => mockUpdateResponse);

      // Create family data
      final family = {'familyId': 1, 'familyName': 'Test Family 1'};

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => MemberMessageDialog(
                              apiService: mockApiService,
                              userId: 1,
                              family: family,
                            ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
          ),
        ),
      );

      // Tap the button to open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Find the checkbox for the second member (index 1)
      final memberCheckbox = find.byType(CheckboxListTile).at(1);

      // Tap the checkbox to toggle it
      await tester.tap(memberCheckbox);
      await tester.pumpAndSettle();

      // Verify the API was called with the correct parameters
      verify(
        mockApiService.updateMemberMessagePreference(1, 1, memberUserId, false),
      ).called(1);
    });
  });
}
