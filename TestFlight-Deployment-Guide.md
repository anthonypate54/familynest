# FamilyNest TestFlight Deployment Guide

## 🚀 Quick Start Checklist

### 1. **Start Backend & ngrok**
```bash
# Terminal 1: Start Spring Boot backend
cd /path/to/spring-boot-project
./mvnw spring-boot:run

# Terminal 2: Start ngrok with static domain
ngrok http 8080 --domain=familynest.ngrok.io
```

### 2. **Verify ngrok Connection**
```bash
# Test ngrok tunnel
curl -s "https://familynest.ngrok.io/api/members" | head -5

# Should return 401 Unauthorized (means connection works!)
```

### 3. **Build for TestFlight**
```bash
cd familynest

# Build IPA file
flutter build ipa --release

# Verify new IPA was created
ls -la build/ios/ipa/familynest.ipa
```

### 4. **Upload to TestFlight**
```bash
# Copy IPA to desktop for easy access
cp familynest/build/ios/ipa/familynest.ipa ~/Desktop/

# Open Apple Transporter
open -a "Transporter"
```

**In Apple Transporter:**
1. Click **"+"** or drag `familynest.ipa` from Desktop
2. Wait for validation (2-3 minutes)
3. Click **"Deliver"** 
4. Wait for upload completion
5. Look for **"Delivery Successful"** message

### 5. **Configure in App Store Connect**
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Apps** → **NestFamily**
3. Click **TestFlight** tab
4. Find new build under **"iOS"** section
5. Click on build number (e.g., "1.0.0 (97)")
6. Add **"What to Test"** notes
7. Click **"Save"**
8. Enable for **Internal Testing**

---

## 🔧 Configuration Files

### Key App Config (`familynest/lib/config/app_config.dart`)
```dart
String get ngrokUrl => "https://familynest.ngrok.io";  // NO SPACE!

String get baseUrl {
  // ... other environments ...
  case Environment.development:
  default:
    return ngrokUrl;  // Use ngrok for all platforms
}
```

### Running Services Check
```bash
# Check Spring Boot is running
lsof -i :8080

# Check ngrok is running  
ps aux | grep ngrok

# Check ngrok tunnel details
curl -s http://localhost:4040/api/tunnels | python3 -m json.tool
```

---

## 🐛 Common Issues & Fixes

### **Issue: "Port 80 connection refused"**
❌ **Wrong**: `ngrok http 80`  
✅ **Correct**: `ngrok http 8080 --domain=familynest.ngrok.io`

### **Issue: Old .ipa file timestamp**  
```bash
# Use specific IPA build command
flutter build ipa --release
# NOT just: flutter build ios --release
```

### **Issue: TestFlight can't connect**
- Check `AppConfig.baseUrl` returns ngrok URL
- Rebuild with current working config
- No `--dart-define` needed (not implemented in code)

### **Issue: Media not loading**
- Both API and media use same ngrok URL
- Check `AppConfig.mediaBaseUrl` returns ngrok URL

### **Issue: Build not appearing in App Store Connect**
- Wait 5-10 minutes after "Delivery Successful"
- Refresh App Store Connect page
- Check **TestFlight** tab, not **App Store** tab
- Look under **iOS** builds section

### **Issue: "Processing" status stuck**
- Normal processing: 5-15 minutes
- If stuck >30 minutes, check Apple Developer forums
- Try uploading with different build number

### **Issue: TestFlight app not installing**
- Ensure device UDID is in developer portal
- Check device iOS version compatibility
- Verify internal testing is enabled
- Try removing/re-adding tester

---

## 📱 Platform Configurations

### Current Working Setup:
- **Local Development**: `https://familynest.ngrok.io`
- **Android Emulator**: `https://familynest.ngrok.io` 
- **TestFlight**: `https://familynest.ngrok.io`
- **Backend**: `localhost:8080`

### Important URLs:
- **ngrok Admin**: http://localhost:4040
- **API Base**: https://familynest.ngrok.io
- **Media Base**: https://familynest.ngrok.io

---

## 🔄 Complete Deployment Workflow

### **Daily Development**
1. Start Spring Boot backend
2. Start ngrok: `ngrok http 8080 --domain=familynest.ngrok.io`
3. Run Flutter: `cd familynest && flutter run`

### **TestFlight Deployment**
1. Ensure backend + ngrok running
2. Test on local emulator first
3. Build: `flutter build ipa --release`
4. Copy IPA to Desktop: `cp familynest/build/ios/ipa/familynest.ipa ~/Desktop/`
5. Upload via Apple Transporter (see detailed steps above)
6. Configure in App Store Connect (see detailed steps above)
7. Wait for Apple processing (~5-10 minutes)
8. Download TestFlight app on device
9. Test login and media loading

### **Troubleshooting Steps**
1. Check backend: `curl localhost:8080/api/members`
2. Check ngrok: `curl https://familynest.ngrok.io/api/members`
3. Check app config: Search for "baseUrl" in Flutter logs
4. Rebuild if config changed
5. Fresh upload to TestFlight

---

## 💰 Service Costs

- **Apple Developer**: $99/year
- **ngrok Pro**: $8/month (for static domain)
- **TestFlight**: Free (included with Apple Developer)

---

## 📋 File Locations

```
familynest/
├── lib/config/app_config.dart          # Main app configuration
├── lib/config/env_config.dart          # Environment config (uses .env)
├── build/ios/ipa/familynest.ipa        # Upload this to TestFlight
├── ios/Runner.xcodeproj/project.pbxproj # Bundle ID config
├── pubspec.yaml                         # Version number (line 17)
└── ios/Runner/Info.plist               # CFBundleVersion (build number)
```

## 🔢 Version Management

### **Increment Build Number** (Required for each upload)
```bash
# Current: version: 1.0.0+97
# Next upload should be: version: 1.0.0+98

# Edit pubspec.yaml line 17:
version: 1.0.0+98
```

### **App Store Connect Build Status**
- **Processing**: Apple is scanning the build (~5-15 min)
- **Ready to Submit**: Build is ready for internal testing
- **Testing**: Available to internal/external testers
- **Rejected**: Failed Apple's automated review

### **TestFlight Limits**
- **Internal testers**: Up to 100 (Apple Developer team)
- **External testers**: Up to 10,000 (requires App Review)
- **Build expiry**: 90 days after upload
- **Active builds**: Up to 150 per app

---

## 🎯 Success Indicators

✅ **Backend**: `lsof -i :8080` shows Java process  
✅ **ngrok**: `curl https://familynest.ngrok.io/api/members` returns 401  
✅ **Build**: `ls -la familynest/build/ios/ipa/familynest.ipa` shows recent timestamp  
✅ **TestFlight**: App connects and media loads  

---

## 🆘 Emergency Commands

```bash
# Kill all Flutter processes
pkill -f flutter

# Restart ngrok
pkill ngrok
ngrok http 8080 --domain=familynest.ngrok.io

# Clean Flutter build
cd familynest && flutter clean && flutter pub get

# Fresh TestFlight build
cd familynest && flutter build ipa --release
```

---

*Last Updated: June 2025*  
*ngrok Domain: familynest.ngrok.io*  
*Bundle ID: com.anthony.familynest* 