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
}
