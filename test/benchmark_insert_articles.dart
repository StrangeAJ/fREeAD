import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:freead/services/database_service.dart';
import 'package:freead/models/article.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Benchmark Article Insertion', () async {
    final dbService = DatabaseService();
    // Initialize DB
    await dbService.database;

    final List<Article> articles = List.generate(
      100,
      (i) => Article(
        id: 'article_$i',
        feedId: 'test_feed_id',
        title: 'Test Article $i',
        url: 'https://example.com/article/$i',
        description: 'Test Description $i',
        publishedDate: DateTime.now(),
        dateAdded: DateTime.now(),
        isRead: false,
        isStarred: false,
      ),
    );

    // Benchmark loop
    final watch = Stopwatch()..start();
    for (final article in articles) {
      await dbService.saveArticle(article);
    }
    watch.stop();
    print('Loop insertion took ${watch.elapsedMilliseconds} ms');

    final watchBatch = Stopwatch()..start();
    await dbService.insertArticlesBatch(articles);
    watchBatch.stop();
    print('Batch insertion took ${watchBatch.elapsedMilliseconds} ms');
  });
}
