# Selah - Cross-Platform Bible Study App

A comprehensive cross-platform Bible study application built with Flutter, featuring the 1769 King James Version of the Bible with rich study tools and offline capabilities.

![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)

## 📖 Features

### Core Bible Study Tools
- **Complete 1769 King James Version** - Full Bible text with accurate verse references
- **Offline Reading** - Downloaded content available without internet connection
- **Cross-Platform** - Works on Android, iOS, Web, Windows, macOS, and Linux

### Study Features
- **Rich Text Notes** - Create and edit detailed study notes with formatting
- **Highlight System** - Mark and categorize important verses with colors
- **Verse History** - Track and revisit previously viewed verses
- **Advanced Search** - Find verses by keywords, phrases, or references
- **Book Navigation** - Easy browsing through all 66 books of the Bible

### Data Management
- **Local SQLite Database** - Fast, offline access to all Bible content
- **Cloud Sync** - Optional Firebase synchronization across devices
- **Data Import** - Import from Olive Tree Bible format
- **Export Capabilities** - Export notes and highlights

### Technical Features
- **Responsive Design** - Optimized for phones, tablets, and desktop
- **Firebase Authentication** - Secure user accounts and data sync
- **Material Design** - Clean, intuitive user interface
- **Performance Optimized** - Fast loading and smooth navigation

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** (3.0 or higher)
- **Dart SDK** (3.0 or higher)
- **Git** for version control

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/selah.git
   cd selah
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase (Optional):**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
   - Download `google-services.json` for Android
   - Download `GoogleService-Info.plist` for iOS/macOS
   - Enable Authentication and Firestore in your Firebase project

4. **Generate app icons (if needed):**
   ```bash
   flutter pub run flutter_launcher_icons:main
   ```

### Running the App

#### Development Mode
```bash
# Run on all platforms
flutter run -d chrome    # Web
flutter run -d windows   # Windows
flutter run -d macos     # macOS
flutter run -d linux     # Linux

# For mobile (requires connected device or emulator)
flutter run -d android   # Android
flutter run -d ios       # iOS (requires Xcode)
```

#### Production Builds

**Android:**
```bash
# APK for sideloading
flutter build apk --release

# App Bundle for Play Store
flutter build appbundle --release
```

**iOS (for sideloading):**
```bash
# Build for iOS
flutter build ios --release

# Create IPA (requires Xcode)
cd build/ios/iphoneos
xcodebuild -exportArchive -archivePath YourApp.xcarchive -exportPath ./export -exportOptionsPlist ExportOptions.plist
```

**macOS:**
```bash
flutter build macos --release
```

**Windows:**
```bash
flutter build windows --release
```

**Linux:**
```bash
flutter build linux --release
```

**Web:**
```bash
# Standard web build
flutter build web --release

# With specific renderer (recommended for better performance)
flutter build web --web-renderer canvaskit --release
```

## 📁 Project Structure

```
selah/
├── lib/
│   ├── main.dart              # App entry point
│   ├── data/                  # Data models and bible content
│   ├── database/              # SQLite database classes
│   ├── models/                # Data models
│   ├── screens/               # UI screens
│   ├── services/              # Business logic services
│   ├── utils/                 # Utility functions
│   └── widgets/               # Reusable UI components
├── assets/                    # App assets (fonts, icons)
├── android/                   # Android-specific files
├── ios/                       # iOS-specific files
├── web/                       # Web-specific files
├── windows/                   # Windows-specific files
├── macos/                     # macOS-specific files
└── linux/                     # Linux-specific files
```

## 🔧 Configuration

### Firebase Setup (Optional)
1. Create a Firebase project
2. Enable Authentication (Email/Password)
3. Enable Firestore Database
4. Download configuration files
5. Place them in the appropriate platform folders

### Platform-Specific Setup

**iOS/macOS:**
- Requires Xcode 12+ for development
- Enable "Automatically manage signing" in Xcode

**Android:**
- Minimum SDK: API 22 (Android 5.1)
- Target SDK: Latest stable version

**Web:**
- Requires modern browser support
- Optimized for Chrome, Firefox, Safari, Edge

## 📱 Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Stable | Minimum API 22 |
| iOS      | ✅ Stable | iOS 11+ |
| Web      | ✅ Stable | Modern browsers |
| Windows  | ✅ Stable | Windows 10+ |
| macOS    | ✅ Stable | macOS 10.14+ |
| Linux    | ✅ Stable | Most modern distributions |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests with improvements, bug fixes, or new features.

**How to contribute:**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is released into the public domain under the [Unlicense](LICENSE). You are free to use, modify, and distribute this software for any purpose without restriction.

## 🙏 Acknowledgments

- **1769 King James Version** - Public domain Bible text
- **Flutter Team** - For the excellent cross-platform framework
- **Firebase** - For cloud services and authentication
- **Open Source Community** - For the many libraries that make this possible

## 🐛 Issues & Support

If you encounter any problems or have suggestions:

1. Check existing issues on GitHub
2. Create a new issue with detailed description
3. Include steps to reproduce any bugs
4. Specify your platform and Flutter version

## 📊 Build Status

This project uses GitHub Actions for continuous integration and multi-platform builds.

---

**Made with ❤️ for Bible study and reflection**
