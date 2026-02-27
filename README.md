# Selah - Cross-Platform Bible Study App

A cross-platform Bible study application built with Flutter with no strings attached (no ads, no analytics, no gated features).

Supports completely offline install and functionality and also offers free online sync services (for as long as the service can be supported: currently using the free tier on Supabase: https://supabase.com/pricing).

Note also that Selah has built-in data export and import functionality so you do not have to use the online sync service to backup/restore your saved highlights, notes, history, or saved searches (exported data uses a simple, portable JSON format).

- Selah is currently in open beta and your thoughts/contributions/bug reports would be helpful and will shape the future of the app.
  - We are especially in need of users to test the app on MacOS desktop and iOS mobile platforms!
- Selah currently does not have self-installing or self-updating features.
  -  Fixes and features are being added regularily so check for new releases periodically.
- Use the "Issues" tab to report any problem you may have with the app or even if you need assitance installing, running, or using the app.

![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)

## 📖 Features

### Core Bible Study Tools
- **AV1769 King James Version** - With the words of our Lord coloured in red.
- **Offline Reading** - The App contains everything you need, no internet connection required (except to use the online features like account-based sync).
- **Cross-Platform** - Runs, looks the same, and has all the same features on all platforms (Android, iOS, Web, Windows, macOS, and Linux). Seemlessly adapts to different platforms and screen sizes.

### Study Features
- **Rich Text Notes** - Verse-level note support with automatic verse reference linker
- **Highlight System** - Support for Word-level highlighting with customizeable colours
- **TSK Cross references** - Optionally show TSK (Treasury of Scripture Knowledge) references below each verse. Click-able links are automatically created for TSK references the same as they are for user notes.
- **Verse History** - Track and revisit previously viewed verses
- **Simple/Advanced Search** - Find verses by keywords or phrases with or without using advanced modes (Regular expressions; Nearby mode searches for two or more supplied words within three verses of eachother eg. graven carved)
- **Book Navigation** - Easy browsing through all 66 books of the Bible using a visual grid, list layout, and/or manually entering a reference
- **Full Touch-screen support** - Built from the ground up to be both touch-screen and non-touch-screen friendly
- **Seemless, transparent, account based online sync features** - Sign in to the same account on multiple devices and they will all automatically sync with eachother. Accounts and sync are both secure and free (provided by Supabase free tier which does have limits).

### Data Management
- **Local SQLite Database** - All user data is saved in easy to read and understand sqlite databases. No encryption or obfuscation.
- **Cloud Sync** - Optional Supabase synchronization across devices
- **Data Export/Import** - Export some or all of your data to a backup file and easily import it anywhere else. Import from Olive Tree Bible format is also supported (you will need to obtain your backup file from the Olive Tree Bible web site)

### Technical Features
- **Responsive Design** - Optimized for phones, tablets, and desktop
- **Many Customizeable features** - Colors, fonts, and more.
- **Supabase Authentication** - Secure user accounts and data sync
- **Material Design** - Clean, intuitive user interface
- **Performance Optimized** - Fast loading and smooth navigation due to a simple yet robust design

## 📱 Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Stable | Minimum API 22 (5.1 untested; 8.1.1 tested) |
| iOS      | ✅ Stable | iOS 11+ (18 tested) |
| Web      | ✅ Stable | Modern browsers (Chrome & Firefox on Apache tested; electron-forge (Windows) tested) |
| Windows  | ✅ Stable | Windows 10+ (10 untested; 11 tested) |
| macOS    | ✅ Stable | macOS 10.14+ (untested) |
| Linux    | ✅ Stable | All distributions (Arch/Manjaro/CachyOS, Debian 12+, Ubuntu 22.04+ tested) |


## 🚀 Getting Started

- Visit the "Releases" section, download the file appropriate for your target platform, and manually install and run the application. While in Beta, the app does not come with any self-installing or self-updating capabilities. RPM based Linux distributions will require additional steps (to bypass the fact that the RPM files are not signed).

## 📁 Project Structure

```
selah/
├── lib/
│   ├── main.dart              # App entry point
│   ├── data/                  # Bible data and metadata, TSK data
│   ├── database/              # SQLite database classes
│   ├── models/                # Data models for 3rd party import
│   ├── screens/               # UI screens
│   ├── services/              # Logic services
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


## 🤝 Contributing

Contributions are welcome but it is highly recommended to first discuss it in the issues section before putting in the work for a PR.

Selah is primarily developed on Arch linux and Windows 11. The development environment requirements are

- Visual Studio Code (https://code.visualstudio.com/).
- Flutter (https://docs.flutter.dev/install/manual) (can also be installed easily inside of VS code).
- Optionally install the extensions that VS code recommends while browsing the project folder and source files.

**How to contribute:**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes
5. Submit a pull request

## 📄 License

This project is released into the public domain under the [Unlicense](LICENSE). You are free to use, modify, and distribute this software for any purpose without restriction.

## 🐛 Issues & Support

If you encounter any problems or have suggestions:

1. Check existing issues on GitHub
2. Create a new issue with detailed description
3. Include steps to reproduce any bugs
4. Specify your platform and Flutter version

## 📊 Build Status

This project uses GitHub Actions for continuous integration and multi-platform builds. Check the Releases section for the latest release or clone the repository to build it yourself.

---
