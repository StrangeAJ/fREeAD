import 'package:flutter/material.dart';
import '../services/full_article_service.dart';

class FullArticleTestScreen extends StatefulWidget {
  const FullArticleTestScreen({super.key});

  @override
  State<FullArticleTestScreen> createState() => _FullArticleTestScreenState();
}

class _FullArticleTestScreenState extends State<FullArticleTestScreen> {
  final _urlController = TextEditingController();
  final _fullArticleService = FullArticleService();
  String? _result;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Set a test URL
    _urlController.text = 'https://example.com/article';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testFullArticle() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final content = await _fullArticleService.fetchFullArticleContent(url);
      setState(() {
        _result = content ?? 'No content extracted';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Article Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Article URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testFullArticle,
              child: _isLoading 
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading...'),
                    ],
                  )
                : const Text('Test Full Article'),
            ),
            const SizedBox(height: 16),
            if (_result != null) ...[
              Text(
                'Result:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _result!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
