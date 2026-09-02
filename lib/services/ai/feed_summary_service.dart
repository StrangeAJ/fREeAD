import '../../models/article.dart';
import '../../models/feed_summary.dart';
import '../../utils/app_logger.dart';
import '../database_service.dart';
import 'summarization_service.dart';

/// "Digest" summaries of a whole feed, persisted in the `feed_summaries` table.
class FeedSummaryService {
  static final FeedSummaryService _instance = FeedSummaryService._internal();
  factory FeedSummaryService() => _instance;
  FeedSummaryService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final SummarizationService _summarizationService = SummarizationService();

  /// Existing summary for [feedId], or null.
  Future<FeedSummary?> getFeedSummary(String feedId) async {
    try {
      return await _databaseService.getFeedSummary(feedId);
    } catch (e, st) {
      AppLog.e('Error getting feed summary', e, st);
      return null;
    }
  }

  /// Generates and stores a summary of [articles].
  Future<FeedSummary> generateFeedSummary(
    String feedId,
    List<Article> articles,
  ) async {
    if (articles.isEmpty) {
      throw Exception('No articles available to summarize');
    }

    final combinedText = articles
        .take(10)
        .map((article) => '${article.title}: ${article.description}')
        .join('\n\n');

    if (combinedText.isEmpty) {
      throw Exception('No content available to summarize');
    }

    final summary = await _summarizationService.summarize(combinedText);
    await _databaseService.saveFeedSummary(feedId, summary);

    final savedSummary = await _databaseService.getFeedSummary(feedId);
    if (savedSummary == null) {
      throw Exception('Failed to save feed summary');
    }
    return savedSummary;
  }

  /// Deletes any existing summary and generates a fresh one.
  Future<FeedSummary> refreshFeedSummary(
    String feedId,
    List<Article> articles,
  ) async {
    await _databaseService.deleteFeedSummary(feedId);
    return generateFeedSummary(feedId, articles);
  }

  /// Returns the stored summary when present, otherwise generates one.
  Future<FeedSummary> getOrGenerateFeedSummary(
    String feedId,
    List<Article> articles,
  ) async {
    final existing = await getFeedSummary(feedId);
    if (existing != null) return existing;
    return generateFeedSummary(feedId, articles);
  }

  Future<void> deleteFeedSummary(String feedId) async {
    try {
      await _databaseService.deleteFeedSummary(feedId);
    } catch (e) {
      throw Exception('Failed to delete feed summary: $e');
    }
  }

  Future<bool> hasFeedSummary(String feedId) async =>
      await getFeedSummary(feedId) != null;

  /// Age of the stored summary in hours, or null when there is none.
  Future<int?> getFeedSummaryAgeInHours(String feedId) async {
    final summary = await getFeedSummary(feedId);
    if (summary == null) return null;
    return DateTime.now().difference(summary.updatedAt).inHours;
  }

  Future<bool> isFeedSummaryOld(String feedId, {int maxAgeHours = 24}) async {
    final ageInHours = await getFeedSummaryAgeInHours(feedId);
    if (ageInHours == null) return true;
    return ageInHours > maxAgeHours;
  }
}
