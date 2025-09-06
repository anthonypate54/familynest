#!/bin/bash

# Usage: ./run.sh <platform> [environment]
# Example: ./run.sh android_emulator dev

# Default values
PLATFORM=$1
ENVIRONMENT=${2:-dev}  # Default to dev if not specified

# Check if platform is provided
if [ -z "$PLATFORM" ]; then
  echo "Error: Platform not specified"
  echo "Usage: ./run.sh <platform> [environment]"
  echo "Available platforms: android_emulator, android_physical, ios_simulator, ios_physical, web"
  exit 1
fi

# Check if the platform exists in config.yaml
if ! grep -q "  $PLATFORM:" config.yaml; then
  echo "Error: Platform '$PLATFORM' not found in config.yaml"
  echo "Available platforms: android_emulator, android_physical, ios_simulator, ios_physical, web"
  exit 1
fi

# Extract values from config.yaml
API_URL=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "api_url" | cut -d'"' -f2)
DEVICE_ID=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "device_id" | cut -d'"' -f2)
DESCRIPTION=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "description" | cut -d'"' -f2)
SETUP_COMMAND=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "setup_command" | cut -d'"' -f2)
MEDIA_URL_CONFIG=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "media_url" | cut -d'"' -f2)
BUILD_MODE=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "build_mode" | cut -d'"' -f2)

# Check for empty device_id (skip for release builds)
if [ -z "$DEVICE_ID" ] && [ "$PLATFORM" != "web" ] && [ "$BUILD_MODE" != "release" ] && [ "$BUILD_MODE" != "ios_release" ]; then
  echo "No device ID specified for $PLATFORM in config.yaml"
  
  # List available devices
  echo "Available devices:"
  flutter devices
  
  # Get device list in a more compatible way
  device_list=$(flutter devices | grep "•" | awk -F'•' '{print $2}' | sed 's/^ *//;s/ *$//')
  
  # Save the device IDs to an array
  IFS=$'\n' read -d '' -r -a devices <<< "$device_list"
  
  if [ ${#devices[@]} -eq 0 ]; then
    echo "No devices found. Please connect a device or start an emulator/simulator."
    exit 1
  fi
  
  # Display devices with numbers for selection
  echo "-------------------------------------"
  echo "Please select a device by number:"
  count=1
  for device in "${devices[@]}"; do
    echo "[$count] $device"
    count=$((count + 1))
  done
  echo "-------------------------------------"
  
  # Prompt for device selection
  read -p "Enter device number: " selection
  
  # Validate selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#devices[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
  fi
  
  # Get the selected device ID (adjust for zero-based indexing)
  DEVICE_ID=$(echo "${devices[$((selection-1))]}" | tr -d '[:space:]')
  echo "Selected device ID: $DEVICE_ID"
  
  # Update config.yaml with the provided device ID
  sed -i "" "s/\($PLATFORM:\n.*device_id: \"\)/\1$DEVICE_ID\"/g" config.yaml
fi

echo "=========================================="
echo "Running FamilyNest on $DESCRIPTION"
echo "Platform: $PLATFORM"
echo "Environment: $ENVIRONMENT"
echo "Device ID: $DEVICE_ID"
echo "API URL: $API_URL"
echo "=========================================="

# Run setup command if exists
if [ ! -z "$SETUP_COMMAND" ]; then
  echo "Running setup command: $SETUP_COMMAND"
  # For adb commands with multiple devices, add the -s flag with the device ID
  if [[ "$SETUP_COMMAND" == *"adb"* ]]; then
    SETUP_COMMAND=$(echo "$SETUP_COMMAND" | sed "s/adb /adb -s $DEVICE_ID /g")
  fi
  eval $SETUP_COMMAND
fi

# Always set up port forwarding for Android devices (both emulator and physical)
if [[ "$PLATFORM" == *"android"* ]]; then
  echo "Setting up ADB port forwarding for Android device..."
  adb -s "$DEVICE_ID" reverse tcp:8080 tcp:8080
  if [ $? -eq 0 ]; then
    echo "✅ Port forwarding set up successfully"
    echo "📱 Device can now access backend at http://10.0.2.2:8080"
  else
    echo "⚠️ Warning: Port forwarding setup failed"
    echo "💡 You may need to enable USB debugging on your device"
  fi
fi

# Create a temporary .env file for the app to read
echo "API_URL=$API_URL" > .env
echo "ENVIRONMENT=$ENVIRONMENT" >> .env

# Add MEDIA_URL for ngrok support (required for video playback on all Android devices)
# Use static ngrok URL for all platforms to avoid cleartext HTTP issues
MEDIA_URL="https://familynesngrok.ngrok.io"
echo "MEDIA_URL=$MEDIA_URL" >> .env
echo "✅ Added static ngrok URL for media: $MEDIA_URL"

# Also update .env.development since the app loads this file first
echo "API_URL=$API_URL" > .env.development
echo "ENVIRONMENT=$ENVIRONMENT" >> .env.development
echo "MEDIA_URL=$MEDIA_URL" >> .env.development
echo "✅ Updated .env.development with platform-specific API_URL: $API_URL"

# Run the Flutter app
if [ "$BUILD_MODE" = "release" ]; then
  echo "Building Flutter release APK for staging..."
  flutter build apk --release --dart-define=ENVIRONMENT=staging
  echo "✅ Release APK built successfully!"
  echo "📱 APK location: build/app/outputs/flutter-apk/app-release.apk"
  
  # Create a friendlier copy of the APK
  cp build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/familynest-staging.apk
  echo "📱 Friendly copy: build/app/outputs/flutter-apk/familynest-staging.apk"
elif [ "$BUILD_MODE" = "ios_release" ]; then
  echo "Building Flutter iOS archive for staging..."
  flutter build ios --release --dart-define=ENVIRONMENT=staging
  echo "✅ iOS build completed!"
  echo "📱 Next: Open ios/Runner.xcworkspace in Xcode to archive for TestFlight"
elif [ "$PLATFORM" = "web" ]; then
  RENDERER=$(grep -A 7 "  $PLATFORM:" config.yaml | grep "renderer" | cut -d'"' -f2)
  echo "Running Flutter on web with renderer: $RENDERER"
  flutter run -d chrome --web-renderer $RENDERER
else
  echo "Running Flutter on device: $DEVICE_ID"
  flutter run -d "$DEVICE_ID"
fi

# Restore default .env file after run (for iOS builds and platform detection)
echo "Restoring default .env file..."
cat > .env << 'EOF'
# Default .env file for iOS builds
# App will use platform detection when this is empty
EOF 