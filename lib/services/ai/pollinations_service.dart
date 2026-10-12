class PollinationsService {
  static const int _defaultWidth = 1024;
  static const int _defaultHeight = 1024;

  Future<String> generateImage({
    required String prompt,
    int? width,
    int? height,
  }) async {
    if (prompt.trim().isEmpty) {
      throw Exception('Prompt cannot be empty');
    }

    final w = width ?? _defaultWidth;
    final h = height ?? _defaultHeight;

    if (w < 64 || w > 2048 || h < 64 || h > 2048) {
      throw Exception('Width and height must be between 64 and 2048 pixels');
    }

    final encodedPrompt = Uri.encodeComponent(prompt.trim());
    final seed = DateTime.now().millisecondsSinceEpoch % 1000000;
    final imageUrl =
        'https://image.pollinations.ai/prompt/$encodedPrompt?width=$w&height=$h&nologo=true&seed=$seed';

    return imageUrl;
  }

  String buildImageUrl({
    required String prompt,
    int? width,
    int? height,
    String? seed,
    bool? noShare,
  }) {
    if (prompt.trim().isEmpty) {
      throw Exception('Prompt cannot be empty');
    }

    final w = width ?? _defaultWidth;
    final h = height ?? _defaultHeight;

    if (w < 64 || w > 2048 || h < 64 || h > 2048) {
      throw Exception('Width and height must be between 64 and 2048 pixels');
    }

    final encodedPrompt = Uri.encodeComponent(prompt);
    final effectiveSeed =
        seed ?? (DateTime.now().millisecondsSinceEpoch % 1000000).toString();
    var url =
        'https://image.pollinations.ai/prompt/$encodedPrompt?width=$w&height=$h&nologo=true&seed=$effectiveSeed';

    if (noShare == true) {
      url += '&noshare=true';
    }

    return url;
  }
}
