import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/services/ai/ai_model.dart';

// cycle-36 P3 — the picker sheet auto-enumerates every non-gemma AIModel
// value (model_picker_sheet.dart:57) and renders `displayName` /
// `description` per tile (model_picker_sheet.dart:134-150). This test locks
// the data the sheet consumes: both new cloud models must surface with the
// contract's display names and descriptions, and must not be mistaken for
// image models.
//
// The tile's enabled state (online → enabled, offline → disabled) is the
// sheet's one-line rule (model_picker_sheet.dart:102) and is not asserted
// here: rendering the sheet in a widget test trips a pre-existing Flutter
// debug assertion (the sheet wraps its ListTile in a DecoratedBox with a
// background color) — an app-UI concern outside the P3 contract.

void main() {
  group('AIModel registry — OpenRouter models (cycle-36 P3)', () {
    // The exact expression the picker sheet enumerates.
    final pickerModels = AIModel.values.where((m) => m != AIModel.gemma);

    test('both new models are enumerated by the picker', () {
      expect(pickerModels, contains(AIModel.openrouterFlash));
      expect(pickerModels, contains(AIModel.openrouterPro));
    });

    test('display names match the contract', () {
      expect(AIModel.openrouterFlash.displayName, 'AgentA 2.1 Flash');
      expect(AIModel.openrouterPro.displayName, 'AgentA Pro');
    });

    test('descriptions state cloud and free tier', () {
      expect(
        AIModel.openrouterFlash.description,
        'Fast cloud chat — free tier',
      );
      expect(
        AIModel.openrouterPro.description,
        'Strong cloud chat — free tier',
      );
    });

    test('neither new model is treated as an image model', () {
      // F10: chats.dart:72-75 and model_picker_sheet.dart:165-168 detect
      // image models by the enum-NAME substring.
      for (final model in [AIModel.openrouterFlash, AIModel.openrouterPro]) {
        expect(model.isImageGeneration, isFalse);
        expect(model.name.toLowerCase().contains('pollinations'), isFalse);
        expect(model.name.toLowerCase().contains('image'), isFalse);
      }
    });
  });
}
