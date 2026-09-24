import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aiproject/core/utils/connectivity_service.dart';
import 'package:aiproject/cubit/connectivity/connectivity_cubit.dart';
import 'package:aiproject/cubit/theme/theme_cubit.dart';
import 'package:aiproject/data/models/chat_session_model.dart';
import 'package:aiproject/presentation/dashboard/dashboard.dart';
import 'package:aiproject/repositories/chat_repository.dart';
import 'package:aiproject/services/ai/groq_service.dart';
import 'package:aiproject/services/ai/huggingface_image_service.dart';
import 'package:aiproject/services/ai/model_download_service.dart';
import 'package:aiproject/services/ai/online_ai_service.dart';
import 'package:aiproject/services/ai/pollinations_service.dart';

// Dashboard stale-banner coverage: reload failure with a populated list
// keeps the list visible behind a non-blocking inline banner; the
// full-screen error only appears when there is no data to show.

/// Simple throwing fake for the empty-list failure case.
class FakeChatRepository extends ChatRepository {
  FakeChatRepository(this.chats, {this.failuresRemaining = 0});

  final List<ChatSessionModel> chats;
  int failuresRemaining;

  @override
  Future<List<ChatSessionModel>> getChatsForUser(String userId) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('load failed');
    }
    return chats;
  }
}

/// Sequence fake: fails only on the 1-based call numbers in [failOnCall],
/// otherwise returns [chats]. Lets tests model success-then-failure
/// (stale list) and failure-then-success (retry recovery) deterministically.
class SequenceFakeRepository extends ChatRepository {
  SequenceFakeRepository(this.chats, {this.failOnCall = const {}});

  final List<ChatSessionModel> chats;
  final Set<int> failOnCall;
  int callCount = 0;

  @override
  Future<List<ChatSessionModel>> getChatsForUser(String userId) async {
    callCount++;
    if (failOnCall.contains(callCount)) {
      throw Exception('load failed');
    }
    return chats;
  }
}

ChatSessionModel sampleChat(String id, String title) {
  return ChatSessionModel(
    id: id,
    userId: 'u1',
    title: title,
    lastMessage: 'hello',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

/// Same provider harness as test/dashboard_load_test.dart.
/// Explicit pumps only — never pumpAndSettle (spinner animates forever).
Future<void> pumpDashboard(WidgetTester tester, ChatRepository repo) async {
  final themeCubit = ThemeCubit();
  final connectivityCubit = ConnectivityCubit(ConnectivityService.instance);
  final modelService = ModelDownloadService();
  final onlineService = OnlineAIService(
    GroqService(),
    PollinationsService(),
    HuggingFaceImageService(),
  );
  addTearDown(() async {
    await themeCubit.close();
    await connectivityCubit.close();
    modelService.dispose();
    onlineService.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ChatRepository>.value(value: repo),
        BlocProvider<ThemeCubit>.value(value: themeCubit),
        BlocProvider<ConnectivityCubit>.value(value: connectivityCubit),
        ChangeNotifierProvider<ModelDownloadService>.value(value: modelService),
        ChangeNotifierProvider<OnlineAIService>.value(value: onlineService),
      ],
      child: const MaterialApp(
        home: Dashboard(showBackButton: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Future<void> settleRefresh(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

/// Triggers a pull-to-refresh programmatically: the second _loadChats call.
///
/// RefreshIndicatorState.show() drives its snap animation on the fake
/// vsync clock, so it must NOT be awaited before pumping (that deadlocks).
/// Start it, pump to drive the animation + refresh future, then await it.
Future<void> triggerReload(WidgetTester tester) async {
  final state =
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
  final Future<void> showFuture = state.show();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
  await showFuture;
  await settleRefresh(tester);
}

const String staleBannerText =
    "Couldn't refresh \u2014 showing your saved chats";
const String fullScreenErrorText = "Couldn't load your conversations.";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'readAll':
          return <String, dynamic>{};
        case 'containsKey':
        case 'isProtectedDataAvailable':
          return false;
        default:
          return null;
      }
    });
  });

  group('Dashboard stale banner', () {
    testWidgets(
        'populated list + reload failure keeps list with banner, no full-screen error',
        (tester) async {
      final repo = SequenceFakeRepository(
        [sampleChat('c1', 'Alpine trip')],
        failOnCall: const {2},
      );
      await pumpDashboard(tester, repo);

      // Initial success: list visible, no banner, no full-screen error.
      expect(find.text('Alpine trip'), findsOneWidget);
      expect(find.text(staleBannerText), findsNothing);
      expect(find.text(fullScreenErrorText), findsNothing);

      // Reload fails: stale banner appears, list stays.
      await triggerReload(tester);

      expect(find.text('Alpine trip'), findsOneWidget);
      expect(find.text(staleBannerText), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text(fullScreenErrorText), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(find.text('No conversations yet'), findsNothing);
    });

    testWidgets('empty + load failure shows full-screen error, no banner',
        (tester) async {
      await pumpDashboard(
        tester,
        FakeChatRepository(const [], failuresRemaining: 99),
      );

      expect(find.text(fullScreenErrorText), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text(staleBannerText), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.text('No conversations yet'), findsNothing);
    });

    testWidgets('banner Retry triggers reload and clears banner on success',
        (tester) async {
      final repo = SequenceFakeRepository(
        [sampleChat('c1', 'Alpine trip')],
        failOnCall: const {2},
      );
      await pumpDashboard(tester, repo);
      expect(repo.callCount, 1);

      await triggerReload(tester);
      expect(repo.callCount, 2);
      expect(find.text(staleBannerText), findsOneWidget);

      // Third call succeeds: banner clears, list remains.
      await tester.tap(find.text('Retry'));
      await settleRefresh(tester);

      expect(repo.callCount, 3);
      expect(find.text(staleBannerText), findsNothing);
      expect(find.text(fullScreenErrorText), findsNothing);
      expect(find.text('Alpine trip'), findsOneWidget);
    });
  });
}
