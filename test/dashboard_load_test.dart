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

// Dashboard load-failure coverage (Phase 2 of the silent-load fix).
//
// The production [ChatRepository] is subclassed with [getChatsForUser]
// overridden to throw — its DAO/ConnectivityService internals stay
// untouched and are never reached on the overridden path.

/// Configurable fake: throws [failuresRemaining] times, then returns [chats].
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

ChatSessionModel sampleChat(String id, String title) {
  return ChatSessionModel(
    id: id,
    userId: 'u1',
    title: title,
    lastMessage: 'hello',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

/// Pumps [Dashboard] with the minimum provider set its build needs:
/// ThemeCubit + ChatRepository + ConnectivityCubit (direct), plus
/// ModelDownloadService + OnlineAIService (via OfflineModelBanner).
///
/// Uses explicit pumps only — never pumpAndSettle: the loading spinner
/// animates forever, so pumpAndSettle would hang on the loading frame.
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
  // Let didChangeDependencies fire, the getUserId + repo futures complete,
  // then rebuild with the result.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

/// Same explicit-pump settle after a Retry tap (load is async again).
Future<void> settleRetry(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Dashboard._loadChats awaits LocalChatDao.getUserId(), which falls
  // through to FlutterSecureStorage (SessionManager.currentSession).
  // No platform plugin exists under flutter_test, so answer the channel
  // directly: no stored session → getUserId returns '' immediately and the
  // fake ChatRepository path below proceeds deterministically.
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

  group('Dashboard load states', () {
    testWidgets('repo throws shows error state, never the empty state',
        (tester) async {
      await pumpDashboard(
        tester,
        FakeChatRepository(const [], failuresRemaining: 99),
      );

      expect(
        find.text("Couldn't load your conversations."),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('No conversations yet'), findsNothing);
    });

    testWidgets('throws then succeeds on retry shows the list', (tester) async {
      final repo = FakeChatRepository(
        [sampleChat('c1', 'Alpine trip')],
        failuresRemaining: 1,
      );
      await pumpDashboard(tester, repo);

      // Failure first.
      expect(
        find.text("Couldn't load your conversations."),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await settleRetry(tester);

      // Retry succeeded: error gone, chat listed.
      expect(
        find.text("Couldn't load your conversations."),
        findsNothing,
      );
      expect(find.text('Alpine trip'), findsOneWidget);
      expect(find.text('No conversations yet'), findsNothing);
    });

    testWidgets('success path renders the list', (tester) async {
      await pumpDashboard(
        tester,
        FakeChatRepository([
          sampleChat('c1', 'Alpine trip'),
          sampleChat('c2', 'Weekly review'),
        ]),
      );

      expect(find.text('Alpine trip'), findsOneWidget);
      expect(find.text('Weekly review'), findsOneWidget);
      expect(
        find.text("Couldn't load your conversations."),
        findsNothing,
      );
      expect(find.text('No conversations yet'), findsNothing);
    });

    testWidgets('empty path renders the empty state', (tester) async {
      await pumpDashboard(tester, FakeChatRepository(const []));

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(
        find.text("Couldn't load your conversations."),
        findsNothing,
      );
      expect(find.text('Retry'), findsNothing);
    });
  });
}
