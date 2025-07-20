import '../models/feed_summary.dart';
import '../services/database_service.dart';
import '../services/summarization_service.dart';
import '../models/article.dart';

class FeedSummaryService {
  static final FeedSummaryService _instance = FeedSummaryService._internal();
  factory FeedSummaryService() => _instance;
  FeedSummaryService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final SummarizationService _summarizationService = SummarizationService();

  /// Get existing feed summary from database
  Future<FeedSummary?> getFeedSummary(String feedId) async {
    try {
      return await _databaseService.getFeedSummary(feedId);
    } catch (e) {
      print('Error getting feed summary: $e');
      return null;
    }
  }

  /// Generate and save a new feed summary
  Future<FeedSummary> generateFeedSummary(String feedId, List<Article> articles) async {
    if (articles.isEmpty) {
      throw Exception('No articles available to summarize');
    }

    // Combine article content for summarization
    final combinedText = articles
        .take(10) // Limit to first 10 articles to avoid too much text
        .map((article) => '${article.title}: ${article.description}')
        .join('\n\n');

    if (combinedText.isEmpty) {
      throw Exception('No content available to summarize');
    }

    // Generate summary using the summarization service
    final summary = await _summarizationService.summarize(combinedText);

    // Save to database
    await _databaseService.saveFeedSummary(feedId, summary);

    // Return the updated summary
    final savedSummary = await _databaseService.getFeedSummary(feedId);
    if (savedSummary == null) {
      throw Exception('Failed to save feed summary');
    }

    return savedSummary;
  }

  /// Refresh (regenerate) an existing feed summary
  Future<FeedSummary> refreshFeedSummary(String feedId, List<Article> articles) async {
    // Delete existing summary first
    await _databaseService.deleteFeedSummary(feedId);

    // Generate new summary
    return await generateFeedSummary(feedId, articles);
  }

  /// Get or generate feed summary (checks for existing first)
  Future<FeedSummary> getOrGenerateFeedSummary(String feedId, List<Article> articles) async {
    // Check for existing summary first
    final existing = await getFeedSummary(feedId);
    if (existing != null) {
      return existing;
    }

    // Generate new summary if none exists
    return await generateFeedSummary(feedId, articles);
  }

  /// Delete a feed summary
  Future<void> deleteFeedSummary(String feedId) async {
    try {
      await _databaseService.deleteFeedSummary(feedId);
    } catch (e) {
      throw Exception('Failed to delete feed summary: $e');
    }
  }

  /// Check if a feed has a saved summary
  Future<bool> hasFeedSummary(String feedId) async {
    final summary = await getFeedSummary(feedId);
    return summary != null;
  }

  /// Get the age of the feed summary in hours
  Future<int?> getFeedSummaryAgeInHours(String feedId) async {
    final summary = await getFeedSummary(feedId);
    if (summary == null) return null;

    final now = DateTime.now();
    final difference = now.difference(summary.updatedAt);
    return difference.inHours;
  }

  /// Check if feed summary is old (older than specified hours)
  Future<bool> isFeedSummaryOld(String feedId, {int maxAgeHours = 24}) async {
    final ageInHours = await getFeedSummaryAgeInHours(feedId);
    if (ageInHours == null) return true; // No summary exists
    return ageInHours > maxAgeHours;
  }
}
