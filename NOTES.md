# FamilyNest Flutter App Development Notes

## Emulator Commands

### iOS Emulator Commands

Open the iOS Simulator application:
```
open -a Simulator
```

List available simulator devices:
```
xcrun simctl list devices
```

Boot a specific simulator (for example, iPhone 16 Plus):
```
xcrun simctl boot "iPhone 16 Plus"
```

Run your Flutter app on it:
```
cd /Users/Anthony/projects/familynest-project/familynest
flutter run -d "iPhone 16 Plus"
```

### Android Emulator Commands

List available Android emulators:
```
flutter emulators
```

Start a specific Android emulator:
```
flutter emulators --launch <emulator_id>
```

Alternative way to list emulators:
```
$ANDROID_HOME/emulator/emulator -list-avds
```

Alternative way to start an emulator:
```
$ANDROID_HOME/emulator/emulator -avd <emulator_name>
```

Check if the emulator is running:
```
flutter devices
```

Run your Flutter app on the Android emulator:
```
cd /Users/Anthony/projects/familynest-project/familynest
flutter run -d "sdk gphone64 x86 64"
```

Or using the device ID:
```
flutter run -d emulator-5554
```

## Development Notes

### Family Management
- Implemented "1+Many" family model
  - Users can create one family as an admin
  - Users can join multiple families as a member
  - UI uses tabs to separate viewing families from creating families

### Error Handling
- Added user-friendly error messages for family joining
- Improved invitation handling

### API Notes
- Base URL for Android: http://10.0.0.81:8080
- Base URL for iOS: http://localhost:8080

## TODO

- Complete family management implementation
- Test with multiple users
- Enhance UI/UX for mobile devices
