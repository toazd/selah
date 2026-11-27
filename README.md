# Selah - Cross-Platform Bible Study App
![Platform Support](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-Unlicense-green)

Selah is a cross-platform, touch-friendly, King James Version only Bible study application built with <a href="https://docs.flutter.dev/">Flutter</a>. It is intuitive and simple by default but also has unique and advanced features tucked away to support efficient, distraction-free Bible study. Selah is completely free and has no ads, no analytics, and no gated features.

Selah is named as such because the word itself means a musical refrain and/or to pause and reflect and as it is written in the first Psalm "...in his law doth he meditate day and night.".

The purpose of Selah is to faithfully preserve the King James Version (colloquially known as the King James Bible or the Cambridge Concord edition) and to provide tools to make studying it more efficient.

## 📖 Features

### Core Bible Study Tools
- **King James Version** - With the words of the Lord Jesus Christ colored in red.
- **Offline Reading** - No internet connection required if you don't want to use the online account sync feature
- **Cross-Platform** - Runs, looks the same, and has all the same features on all platforms (Android, iOS, Web, Windows, macOS, and Linux). Seemlessly adapts to different platforms and screen sizes.

### Study Features
- **Rich Text Notes** - Verse-level note support with automatic verse reference linker
- **Highlight System** - Support for word-level highlighting with customizeable colors
- **TSK Cross references** - Optionally show TSK (Treasury of Scripture Knowledge) references below each verse
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

## Which digital KJV does this app use?
For its textual source this app uses a text that is exactly equivalent to the Cambridge Concord text, which differs from the "1769 Oxford" / "1769 KJV" (Blayney revisions) and the Pure Cambridge edition. Some publishers, like Christian Art Publishers/Christian Art Gifts, do not disclose the source of their text but they still use the exact equivalent of the Cambridge Concord text (I can't verify that ALL Christian Art Publishers ISBNs use the Cambridge Concord text - only the ones I've purchased so far).

**Many** digital KJV text source files online (and apps that contain a KJV) are **mislabeled** as "1769 Oxford" / "1769 KJV" / "AV 1769" (because they are NOT exactly equivalent to the 1769 Oxford print, which is easy to verify) or are mixed with the 1900+ Pure Cambridge Edition (PCE) changes ([here](https://cheerful-wmcdannell.wordpress.com/wp-content/uploads/2025/09/cambridgeconcord_vs_cambridgepce.pdf) is a concise report of the most important differences between the Concord and the PCE).

To check whether a digital or printed source text matches the Cambridge Concord text, simply verify that your text matches BOTH checklists below. Note that these checklists are not comprehensive, they are meant only as a quick reference aid for identifying whether a textual source is Cambridge Concord, 1769 Oxford (Blayney), or Pure Cambridge Edition (PCE) based.

### 1. Cambridge-based checklist (rules out 1769 Oxford & Americanized KJVs)
- [ ] **Joshua 19:2** — Reads `or Sheba` *(not `and Sheba`)*
- [ ] **Ruth 3:15** — Reads `and she went into the city` *(not `he went`)*
- [ ] **1 Samuel 2:13** — Reads `priests' custom` *(plural possessive, not `priest's`)*
- [ ] **2 Chronicles 33:19** — Reads `all his sin` *(singular, not `sins`)*
- [ ] **Jeremiah 34:16** — Reads `whom ye had set at liberty` *(not `whom he`)*
- [ ] **Nahum 3:16** — Reads `flieth away` *(not `fleeth away`)*
- [ ] **Matthew 26:39** — Reads `went a little further` *(not `farther`)*
- [ ] **Matthew 26:73** — Reads `thy speech bewrayeth thee` *(not `betrayeth`)*
- [ ] **Genesis 8:21** — Uses British spelling `savour` *(not American `savor`)*

### 2. Pre-1900 Concord checklist (rules out 1900+ Pure Cambridge Edition)
- [ ] **Ezra 2:26** — Reads `Ramah and Gaba` *(not `Geba`)*
- [ ] **Acts 11:12, 11:28 & 1 John 5:8** — Capitalizes `Spirit` *(not lowercase `spirit`)*
- [ ] **Genesis 24:57** *(and ~65 other verses)* — Uses `enquire` / `enquiry` *(not `inquire` / `inquiry`)*
- [ ] **Isaiah 9:6** *(and ~22 other verses)* — Uses `Counsellor` *(not `Counseller`)*
- [ ] **Numbers 6:5** *(and 5 other verses)* — Uses `razor` *(not `rasor`)*
- [ ] **Ezekiel 47:3 & Acts 3:7** — Uses `ankles` / `ankle` *(not `ancles` / `ancle`)*
- [ ] **Ezra 6:4 & 6:8** — Uses `expenses` *(not `expences`)*
- [ ] **Leviticus 27:26, Numbers 30:2 & Haggai 1:13** — Uses `LORD’S` *(capital `S`, not `LORD’s`)*
- [ ] **Jeremiah 38:5** — Ends with a period `.` *(not a question mark `?`)*
- [ ] **Mark 2:1** — Reads `into Capernaum after some days` *(no comma after `Capernaum`)*
- [ ] **1 Corinthians 15:27** — Reads `when he saith all things` *(no comma after `saith`)*
