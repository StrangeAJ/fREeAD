// Test script to verify RSS parsing - simplified version
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

void main() async {
  print('Testing RSS parsing...');
  
  final dio = Dio();
  
  try {
    // Test with a simple RSS feed using CORS proxy
    final url = 'https://feeds.bbci.co.uk/news/rss.xml';
    final corsProxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
    
    print('Fetching RSS feed: $corsProxyUrl');
    final response = await dio.get(corsProxyUrl);
    print('Response status: ${response.statusCode}');
    print('Response data length: ${response.data.toString().length}');
    
    final document = XmlDocument.parse(response.data);
    
    // Try RSS 2.0 format
    final rssItems = document.findAllElements('item');
    print('Found ${rssItems.length} RSS items');
    
    if (rssItems.isNotEmpty) {
      final firstItem = rssItems.first;
      final title = firstItem.findElements('title').first.text;
      final link = firstItem.findElements('link').first.text;
      final description = firstItem.findElements('description').first.text;
      
      print('First article:');
      print('  Title: $title');
      print('  Link: $link');
      print('  Description: ${description.substring(0, 100)}...');
    }
    
    print('RSS parsing test completed successfully!');
  } catch (e) {
    print('Error: $e');
  }
}
