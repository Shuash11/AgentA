import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/core/utils/chat_error_classifier.dart';

void main() {
  group('ChatErrorClassifier.isOfflineNotReady', () {
    test('matches every offline substring', () {
      expect(
        ChatErrorClassifier.isOfflineNotReady(
          'Exception: offline model is not ready yet',
        ),
        isTrue,
      );
      expect(
        ChatErrorClassifier.isOfflineNotReady('offline ai model is not ready'),
        isTrue,
      );
      expect(
        ChatErrorClassifier.isOfflineNotReady(
          'offline mode is enabled, connect first',
        ),
        isTrue,
      );
      expect(
        ChatErrorClassifier.isOfflineNotReady(
          'AgentA Offline AI is still getting ready',
        ),
        isTrue,
      );
      expect(
        ChatErrorClassifier.isOfflineNotReady('offline model is not installed'),
        isTrue,
      );
      expect(
        ChatErrorClassifier.isOfflineNotReady(
          'offline model failed to load weights',
        ),
        isTrue,
      );
    });

    test('matches case-insensitively', () {
      expect(
        ChatErrorClassifier.isOfflineNotReady('OFFLINE MODEL IS NOT READY'),
        isTrue,
      );
    });

    test('rejects unrelated errors', () {
      expect(ChatErrorClassifier.isOfflineNotReady('no internet'), isFalse);
      expect(ChatErrorClassifier.isOfflineNotReady('api error 500'), isFalse);
      expect(ChatErrorClassifier.isOfflineNotReady(''), isFalse);
      expect(
        ChatErrorClassifier.isOfflineNotReady('something else went wrong'),
        isFalse,
      );
    });
  });

  group('ChatErrorClassifier.friendly', () {
    test('offline-not-ready maps to the frozen brand message', () {
      expect(
        ChatErrorClassifier.friendly('offline model is not ready'),
        ChatErrorClassifier.offlineNotReadyMessage,
      );
      expect(
        ChatErrorClassifier.friendly('OFFLINE MODEL FAILED TO LOAD'),
        ChatErrorClassifier.offlineNotReadyMessage,
      );
      expect(
        ChatErrorClassifier.offlineNotReadyMessage,
        'AgentA Offline AI is still getting ready. Try again in a moment.',
      );
    });

    test('offline takes precedence over no-internet', () {
      expect(
        ChatErrorClassifier.friendly(
          'offline model is not ready; no internet either',
        ),
        ChatErrorClassifier.offlineNotReadyMessage,
      );
    });

    test('no-internet without offline maps to the offline hint', () {
      expect(
        ChatErrorClassifier.friendly('SocketException: no internet access'),
        'No internet. If your offline model is installed, try again in a moment.',
      );
    });

    test('groq key not configured', () {
      expect(
        ChatErrorClassifier.friendly('groq api key not configured on server'),
        'Chat service is not configured correctly.',
      );
    });

    test('huggingface credits / rate-limit', () {
      expect(
        ChatErrorClassifier.friendly('huggingface: credits exhausted for now'),
        'HD image generation: free limit reached. Try again later or use standard image generation.',
      );
      expect(
        ChatErrorClassifier.friendly('HF_TOKEN rate limit exceeded'),
        'HD image generation: free limit reached. Try again later or use standard image generation.',
      );
    });

    test('huggingface warming / timed-out', () {
      expect(
        ChatErrorClassifier.friendly('huggingface model warming up'),
        'HD image generation is warming up. Try again in a moment.',
      );
      expect(
        ChatErrorClassifier.friendly('huggingface request timed out'),
        'HD image generation is warming up. Try again in a moment.',
      );
    });

    test('huggingface not-configured / invalid', () {
      expect(
        ChatErrorClassifier.friendly('huggingface token not configured'),
        'HD image generation is not configured correctly.',
      );
      expect(
        ChatErrorClassifier.friendly('huggingface invalid token'),
        'HD image generation is not configured correctly.',
      );
    });

    test('huggingface default', () {
      expect(
        ChatErrorClassifier.friendly('huggingface inference failed'),
        'HD image generation failed. Please try again.',
      );
      expect(
        ChatErrorClassifier.friendly('hf_token blew up'),
        'HD image generation failed. Please try again.',
      );
    });

    test('pollinations', () {
      expect(
        ChatErrorClassifier.friendly('pollinations gateway timeout'),
        'Image generation failed. Please try again.',
      );
    });

    test('api-error / service-error', () {
      expect(
        ChatErrorClassifier.friendly('api error 500 from model'),
        'The selected AI model failed to respond. Please try again.',
      );
      expect(
        ChatErrorClassifier.friendly('service error unavailable'),
        'The selected AI model failed to respond. Please try again.',
      );
    });

    test('unknown falls back to the generic model message', () {
      expect(
        ChatErrorClassifier.friendly('some brand new failure mode'),
        'The selected AI model failed to respond. Please try again.',
      );
      expect(
        ChatErrorClassifier.friendly(''),
        'The selected AI model failed to respond. Please try again.',
      );
    });

    test('matching is case-insensitive', () {
      expect(
        ChatErrorClassifier.friendly('GROQ API KEY NOT CONFIGURED'),
        'Chat service is not configured correctly.',
      );
      expect(
        ChatErrorClassifier.friendly('POLLINATIONS boom'),
        'Image generation failed. Please try again.',
      );
    });
  });

  group('ChatErrorClassifier.friendly — OpenRouter (cycle-36 P3)', () {
    test('key not configured', () {
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter API key not configured. Please set OPENROUTER_API_KEY via --dart-define.',
        ),
        'Chat service is not configured correctly.',
      );
    });

    test('invalid key (401) reads as a configuration problem', () {
      expect(
        ChatErrorClassifier.friendly(
          'Invalid OpenRouter API key. Please check OPENROUTER_API_KEY.',
        ),
        'Chat service is not configured correctly.',
      );
    });

    test('rate limit (429) is not masked by the broad branch', () {
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter rate limit exceeded (free tier: 20/min, 50/day).',
        ),
        'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.',
      );
    });

    test('free quota (402) is not masked by the broad branch', () {
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter free quota exhausted (daily limit or account balance).',
        ),
        'Free chat quota reached for today. Try again tomorrow or switch models.',
      );
    });

    test('forbidden (403)', () {
      expect(
        ChatErrorClassifier.friendly('OpenRouter rejected the request (403).'),
        'The AI service declined this request. Try rephrasing or switch models.',
      );
    });

    test('timeout (408)', () {
      expect(
        ChatErrorClassifier.friendly('OpenRouter request timed out.'),
        'Connection timed out. Check your internet connection.',
      );
    });

    test('unlisted 4xx', () {
      expect(
        ChatErrorClassifier.friendly('OpenRouter request error: 400'),
        'The selected AI model failed to respond. Please try again.',
      );
      expect(
        ChatErrorClassifier.friendly('OpenRouter request error: unknown'),
        'The selected AI model failed to respond. Please try again.',
      );
    });

    test('5xx and the broad fallback', () {
      expect(
        ChatErrorClassifier.friendly('OpenRouter server error: 500'),
        'The AI service is temporarily unavailable. Please try again.',
      );
      expect(
        ChatErrorClassifier.friendly('OpenRouter something unexpected'),
        'The AI service is temporarily unavailable. Please try again.',
      );
    });

    test('empty content after the reasoning budget', () {
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter: the model used its full response budget. Please try again.',
        ),
        'The model used its full response budget. Please try again.',
      );
    });

    test('matching is case-insensitive', () {
      expect(
        ChatErrorClassifier.friendly('OPENROUTER RATE LIMIT exceeded'),
        'Cloud chat is rate limited (free tier: 20 requests/min, 50/day). Wait a moment and try again.',
      );
      expect(
        ChatErrorClassifier.friendly('OPENROUTER API KEY NOT CONFIGURED'),
        'Chat service is not configured correctly.',
      );
    });

    test('openrouter errors never reach the generic catch-all copy', () {
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter rate limit exceeded (free tier: 20/min, 50/day).',
        ),
        isNot('The selected AI model failed to respond. Please try again.'),
      );
      expect(
        ChatErrorClassifier.friendly('OpenRouter server error: 500'),
        isNot('The selected AI model failed to respond. Please try again.'),
      );
      expect(
        ChatErrorClassifier.friendly(
          'OpenRouter API key not configured. Please set OPENROUTER_API_KEY via --dart-define.',
        ),
        isNot('The selected AI model failed to respond. Please try again.'),
      );
    });
  });
}
