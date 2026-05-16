import 'package:gemini_nano_android/gemini_nano_android.dart';

class OnDeviceAIService {
  final GeminiNanoAndroid _gemini = GeminiNanoAndroid();

  Future<bool> isAvailable() async {
    try {
      return await _gemini.isAvailable();
    } catch (e) {
      print('Error checking Gemini Nano availability: $e');
      return false;
    }
  }

  Future<String> summarize(String text) async {
    try {
      final results = await _gemini.generate(
        prompt: "Summarize the following text in a concise, clear manner:\n\n$text",
        temperature: 0.3,
        candidateCount: 1,
      );
      if (results.isNotEmpty) {
        return results.first;
      }
      throw Exception('Empty response from Gemini Nano');
    } catch (e) {
      throw Exception('On-device summarization failed: $e');
    }
  }
}
