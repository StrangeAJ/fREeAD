// Enhanced article extraction test
import '../../lib/services/enhanced_article_service.dart';

void main() async {
  print('Testing enhanced article extraction...');
  
  final service = EnhancedArticleService();
  
  // Test URLs - different website types
  final testUrls = [
    'https://www.bbc.com/news',
    'https://edition.cnn.com/2024/01/01/world/example-article/index.html',
    'https://www.theverge.com/2024/1/1/example-article',
    'https://techcrunch.com/2024/01/01/example-article',
    'https://www.reddit.com/r/technology/comments/example',
  ];
  
  for (final url in testUrls) {
    print('\n' + '='*50);
    print('Testing: $url');
    print('='*50);
    
    try {
      final result = await service.extractArticleContent(url);
      
      if (result != null) {
        print('✅ SUCCESS');
        print('Title: ${result['title']}');
        print('Author: ${result['author']}');
        print('Content length: ${result['length']} characters');
        print('Excerpt: ${result['excerpt']}');
        print('Content preview: ${result['content']?.substring(0, 200) ?? 'N/A'}...');
      } else {
        print('❌ FAILED: No content extracted');
      }
    } catch (e) {
      print('❌ ERROR: $e');
    }
    
    // Add delay to avoid rate limiting
    await Future.delayed(Duration(seconds: 2));
  }
  
  service.dispose();
  print('\n\nTest completed!');
}
