#!/bin/bash

# Script to run the Flutter widget tests for message preferences

set -e

echo "===== Running Message Preferences Widget Tests ====="
echo "Starting test run at $(date)"

# Change to the project root directory
cd "$(dirname "$0")/.."

# Ensure we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "Error: pubspec.yaml not found. Please run this script from the Flutter project root directory."
    exit 1
fi

# Make sure dependencies are up to date
echo "Getting dependencies..."
flutter pub get

# Generate mock classes for testing
echo "Generating mocks..."
flutter pub run build_runner build --delete-conflicting-outputs

# Check if mock generation succeeded
if [ ! -f "test/generate_mocks.mocks.dart" ]; then
    echo "❌ Error: Mock generation failed. Please check the output above for errors."
    exit 1
fi

echo "Copying mock files to ensure they're accessible..."
cp test/generate_mocks.mocks.dart test/message_preferences_test.mocks.dart

# Run just the message preferences tests
echo "Running tests..."
flutter test test/message_preferences_test.dart

# Check if tests passed
if [ $? -eq 0 ]; then
    echo "✅ Message Preferences Widget Tests PASSED"
else
    echo "❌ Message Preferences Widget Tests FAILED"
    exit 1
fi

echo "Test run completed at $(date)" 