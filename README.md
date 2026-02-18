# Selah - Cross-Platform Bible Study App

A cross-platform Bible study application built with Flutter.

## 📱 Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Stable | Minimum API 22 |
| iOS      | ✅ Stable | iOS 11+ |
| Web      | ✅ Stable | Modern browsers |
| Windows  | ✅ Stable | Windows 10+ |
| macOS    | ✅ Stable | macOS 10.14+ |
| Linux    | ✅ Stable | All distributions |

Selah is currently in open beta and your thoughts/contributions/bug reports would be helpful and will shape the future of the app. Use the "Issues" tab to report anything you think might be useful.

![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)

## 📖 Features

### Core Bible Study Tools
- **AV1769 King James Version** - With the words of our Lord coloured in red.
- **Offline Reading** - The App contains everything you need, no internet connection required (except to use the online features like account-based sync).
- **Cross-Platform** - Runs, looks the same, and has all the same features on all platforms (Android, iOS, Web, Windows, macOS, and Linux). Seemlessly adapts to different platforms and screen sizes.

### Study Features
- **Rich Text Notes** - Create and edit detailed study notes with formatting
- **Highlight System** - Mark and categorize important verses with colours
- **Verse History** - Track and revisit previously viewed verses
- **Advanced Search** - Find verses by keywords or phrases with or without using the advanced modes (Regex, Nearby)
- **Book Navigation** - Easy browsing through all 66 books of the Bible
- **Full Touch-screen support** - Built from the ground up to be both touch-screen and non-touch-screen friendly
- **Seemless, transparent, account based online sync features** - Sign in to the same account on multiple devices and they will all automatically sync with eachother

### Data Management
- **Local SQLite Database** - All user data is stored localling in sqlite databases
- **Cloud Sync** - Optional Supabase synchronization across devices
- **Data Export/Import** - Export some or all of your data to a backup file and easily import it anywhere else. Import from Olive Tree Bible format is also supported (you will need to obtain the backup file from the Olive Tree Bible web site)

### Technical Features
- **Responsive Design** - Optimized for phones, tablets, and desktop
- **Supabase Authentication** - Secure user accounts and data sync
- **Material Design** - Clean, intuitive user interface
- **Performance Optimized** - Fast loading and smooth navigation

## 🚀 Getting Started

- Visit the "Releases" section, download the file appropriate for your target platform, and manually install and run the application. While in Beta, the app does not come with any self-installing capabilities. RPM based Linux distributions will require additional steps (to bypass the fact that the RPM files are not signed).

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

## 🐛 Issues & Support

If you encounter any problems or have suggestions:

1. Check existing issues on GitHub
2. Create a new issue with detailed description
3. Include steps to reproduce any bugs
4. Specify your platform and Flutter version

## 📊 Build Status

This project uses GitHub Actions for continuous integration and multi-platform builds. Check the Releases section for the latest release or clone the repository to build it yourself.

---
