# DayMate

A Flutter application for daily routine management including reminders, habits, and sleep tracking.

**Created by Iverson**

## Features

- **Home Dashboard** - Overview of upcoming reminders, completion stats, and daily motivation
- **Reminder List** - Add, edit, complete, and delete reminders with categories (Breakfast, Lunch, Dinner, Sleep, Wake-up, Study, Exercise, Appointment, Custom)
- **Sleep Tracker** - Set bedtime and wake-up times with scheduled notifications
- **Daily Habits** - Track daily habits with progress indicator
- **Profile** - Personal information and app statistics
- **Notifications** - Local scheduled notifications for reminders
- **API Integration** - Fetches daily motivational advice
- **Persistent Storage** - Uses SharedPreferences for local data persistence

## Platform Support

- ✅ Android
- ✅ iOS (via Codemagic cloud build)
- ✅ Web
- ✅ Windows
- ✅ macOS
- ✅ Linux

## Getting Started

### Prerequisites

- Flutter SDK 3.44.2 or later
- Dart 3.12.2 or later

### Installation

```bash
git clone https://github.com/vrsnzz19-glitch/Final-Projectcc302.git
cd Final-Projectcc302
flutter pub get
flutter run
```

### iOS Build (via Codemagic)

Since iOS builds require macOS and Xcode, this project is configured for [Codemagic](https://codemagic.io/) cloud builds.

1. Connect your GitHub repository to Codemagic
2. Configure the `codemagic.yaml` workflow
3. Add Apple Developer certificates and provisioning profiles in Codemagic environment variables
4. Trigger a build

See [Codemagic Setup Guide](#codemagic-setup) below.

## Project Structure

```
lib/
  main.dart          # Main application entry point and all screens
test/
  widget_test.dart   # Widget tests
ios/
  Runner/            # iOS project configuration
  Runner.xcodeproj/  # Xcode project
android/
  app/               # Android project configuration
codemagic.yaml       # Codemagic CI/CD configuration
export_options.plist # iOS export options for App Store distribution
```

## Dependencies

- `flutter_local_notifications` - Cross-platform local notifications
- `shared_preferences` - Local data persistence
- `http` - API requests for daily advice
- `timezone` - Timezone handling for scheduled notifications
- `cupertino_icons` - iOS-style icons

## Codemagic Setup

### Required Environment Variables (in Codemagic UI)

| Variable | Description |
|----------|-------------|
| `CERTIFICATE_PRIVATE_KEY` | Base64-encoded .p12 certificate |
| `CERTIFICATE_PASSWORD` | Password for the .p12 certificate |
| `PROVISIONING_PROFILE` | Base64-encoded .mobileprovision profile |
| `APP_STORE_CONNECT_API_KEY` | App Store Connect API key (base64) |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | API Key Issuer ID |
| `TEAM_ID` | Apple Developer Team ID |
| `PROVISIONING_PROFILE_SPECIFIER` | Provisioning profile name/UUID |

### Workflows

- **ios-unsigned** - Quick validation build without code signing
- **ios-signed** - Full App Store / TestFlight build with code signing
- **ios-debug** - Debug build for testing

### Building for iOS

```bash
# Local unsigned build (requires macOS)
flutter build ipa --no-codesign --release

# With Codemagic - push to GitHub and trigger workflow
git push origin main
```

## License

This project is created by Iverson for educational purposes.
