# Selah - Cross-Platform Bible Study App
![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)
<br>Simple and intuitive by default<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 125234" src="https://github.com/user-attachments/assets/2b8b5bca-f51d-41e2-99ec-2b56c604e4dd" />
<br>Supports many formatting options in notes<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 125541" src="https://github.com/user-attachments/assets/357b3b7b-1bf8-4a8e-920e-70e1224b5b37" />
<br>Customizable UI colors<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 125738" src="https://github.com/user-attachments/assets/65f6d905-bf91-48f8-93c0-8c00c80ba9b8" />
<br>Customizable highlight colors<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 125732" src="https://github.com/user-attachments/assets/6a5cfb78-5d66-4883-bdb4-ceb2fbec9b13" />
<br>Customizable fonts<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 125743" src="https://github.com/user-attachments/assets/33e6058d-4369-49ea-900d-8b63a36f3f01" />
<br>Multiple screens side by side<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 130946" src="https://github.com/user-attachments/assets/51c87da5-6804-4a38-8c4d-59b4e70cc835" />
<br>Multiple screens stacked<br>
<img width="480" height="300" alt="Screenshot 2026-04-21 130959" src="https://github.com/user-attachments/assets/e88fb8cf-a659-4dcc-958e-f72bb62e4a58" />

Selah is a cross-platform Bible study application built with Flutter with no strings attached (no ads, no analytics, no gated features) and many features built in to support efficient, distraction-free Bible study.

Supports completely offline install and functionality and also offers free online sync services (for as long as the service can be supported: currently using the free tier on Supabase: https://supabase.com/pricing).

Note also that Selah has built-in data export and import functionality so you do not have to use the online sync service to backup/restore your saved highlights, notes, history, or saved searches (exported data uses a simple, portable JSON format).

- Selah is currently in open beta and your thoughts/contributions/bug reports would be helpful and will shape the future of the app.
  - We are especially in need of users to test the app on MacOS desktop and iOS mobile platforms!
- Selah currently does not have self-installing or self-updating features.
  -  Fixes and features are being added regularily so check for new releases periodically.
- Use the "Issues" tab to report any problem you may have with the app or even if you need assitance installing, running, or using the app.

## 📖 Features

### Core Bible Study Tools
- **AV1769 King James Version** - With the words of our Lord colored in red.
- **Offline Reading** - No internet connection required if you don't want to use the online account sync feature
- **Cross-Platform** - Runs, looks the same, and has all the same features on all platforms (Android, iOS, Web, Windows, macOS, and Linux). Seemlessly adapts to different platforms and screen sizes.

### Study Features
- **Rich Text Notes** - Verse-level note support with automatic verse reference linker
- **Highlight System** - Support for word-level highlighting with customizeable colors
- **TSK Cross references** - Optionally show TSK (Treasury of Scripture Knowledge) references below each verse
- **Verse History** - Track and revisit previously viewed verses
- **Simple/Advanced Search** - Find verses by keywords or phrases with or without using advanced modes (Regular expressions; Nearby mode searches for two or more supplied words within three verses of eachother eg. graven carved)
- **Book Navigation** - Easy browsing through all 66 books of the Bible using a visual grid, list layout, or manually entering a reference
- **Full Touch-screen support** - Built from the ground up to be both touch-screen and non-touch-screen friendly
- **Seemless, transparent, account based online sync features** - Sign up using a free account and use that account across multiple devices (no email required)

### Data Management
- **Local SQLite Database** - All user data is saved in easy to read and understand sqlite databases. No encryption or obfuscation
- **Cloud Sync** - Optional Supabase synchronization across devices. Sign in to the same account on multiple devices and they will all seemlessly stay in sync
- **Data Export/Import** - Export some or all of your data to a backup file (compressed JSON) and easily import it anywhere else. Import from Olive Tree Bible format is also supported but you will have to obtain your backup file from the Olive Tree Bible web site
- **Data integrity** - Both local and synced data are checked for integrity violations and discarded if anything invalid or corrupted is detected

### Technical Features
- **Responsive Design** - Optimized for phones, tablets, and desktop
- **Many Customizeable features** - Colors, fonts, and more.
- **Supabase Authentication** - Secure user accounts and data sync
- **Material Design** - Clean, intuitive user interface
- **Performance Optimized** - Fast loading and smooth navigation due to a simple yet robust design

## 📱 Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Stable | Minimum API 27 (8.1.1 & 12 tested) |
| iOS      | ✅ Stable | iOS 11+ (18 tested) |
| Web      | ✅ Stable | Modern browsers (Chrome & Firefox on Apache tested; electron-forge (Windows) tested) |
| Windows  | ✅ Stable | Windows 10+ (10 untested; 11 tested) |
| macOS    | ✅ Stable | macOS 10.14+ (untested) |
| Linux    | ✅ Stable | All distributions (Arch/Manjaro/CachyOS, Debian 12+, Ubuntu 22.04+ tested) |


## 🚀 Getting Started

- Visit the "Releases" section, download the file appropriate for your target platform, and manually install and run the application. While in Beta, the app does not come with any self-installing or self-updating capabilities. RPM based Linux distributions will require additional steps (a command line argument; because the RPM files are not signed).

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
