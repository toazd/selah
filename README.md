# Selah - Cross-Platform Bible Study App
![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)

Selah is a cross-platform, touch-friendly Bible study application built with <a href="https://docs.flutter.dev/">Flutter</a>. It is intuitive and simple by default but also has unique and advanced features tucked away to support efficient, distraction-free Bible study. Selah is completely free and has no ads, no analytics, and no gated features.

## 📖 Features

### Core Bible Study Tools
- **AV1769 King James Version** - With the words of our Lord colored in red.
- **Offline Reading** - No internet connection required if you don't want to use the online account sync feature
- **Cross-Platform** - Runs, looks the same, and has all the same features on all platforms (Android, iOS, Web, Windows, macOS, and Linux). Seemlessly adapts to different platforms and screen sizes.

### Study Features
- **Rich Text Notes** - Verse-level note support with automatic verse reference linker
- **Highlight System** - Support for word-level highlighting with customizeable colors
- **TSK Cross references** - Optionally show TSK (Treasury of Scripture Knowledge) references below each verse
- **Unique Strongs search** - Search by word, reference, or Strong's numbers to reveal everywhere in the Bible those Strong's numbers appear. When doing a word search it first finds all the Strong's numbers associated with that word and then it searches the entire Bible for every verse that contains those Strong's number(s).
- **Strong's definitions** - An extra dialog on the Strong's search screen that allows quickly browsing Strong's definitions.
- **Verse History** - Track and revisit previously viewed verses
- **Simple/Advanced Search** - Find verses by keywords or phrases, with or without using advanced modes (Regular expressions; Nearby mode searches for two or more supplied words within three verses of eachother)
- **Book Navigation** - Easy browsing through all 66 books of the Bible using a visual grid or manually entering a reference. Supports having multiple Bible screens side-by-side or stacked on top of each other.
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
