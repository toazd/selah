import '../database/bible_database.dart';
import 'dart:math';

class RandomVerse {
  /// Returns a randomly selected Bible verse as a formatted string
  /// Format: "Book Chapter:Verse - Verse text"
  /// Uses efficient random selection to avoid loading entire database
  static Future<String> getRandomVerse() async {
    try {
      // Step 1: Get all books
      final books = await BibleDatabase.getBooks();

      if (books.isEmpty) {
        return "No books available";
      }

      // Step 2: Select random book
      final random = Random();
      final randomBook = books[random.nextInt(books.length)];

      // Step 3: Get chapters for selected book
      final chapters = await BibleDatabase.getChapters(randomBook);

      if (chapters.isEmpty) {
        return "No chapters available for $randomBook";
      }

      // Step 4: Select random chapter
      final randomChapter = chapters[random.nextInt(chapters.length)];

      // Step 5: Get verses for selected chapter
      final verses = await BibleDatabase.getVerses(randomBook, randomChapter);

      if (verses.isEmpty) {
        return "No verses available for $randomBook $randomChapter";
      }

      // Step 6: Select random verse
      final randomVerse = verses[random.nextInt(verses.length)];

      // Step 7: Format and return
      return "${randomVerse['book']} ${randomVerse['chapter']}:${randomVerse['verse']}\n${randomVerse['text']}";
    } catch (e) {
      return "Error retrieving random verse: $e";
    }
  }
}
