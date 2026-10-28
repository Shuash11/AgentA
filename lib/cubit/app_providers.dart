import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../core/utils/connectivity_service.dart';
import '../services/ai/ai_service.dart';
import '../services/ai/gemma_service.dart';
import '../services/ai/groq_service.dart';
import '../services/ai/openrouter_service.dart';
import '../services/ai/huggingface_image_service.dart';
import '../services/ai/pollinations_service.dart';
import '../services/ai/offline_ai_service.dart';
import '../services/ai/online_ai_service.dart';
import '../services/ai/model_download_service.dart';
import '../services/sync/sync_service.dart';
import '../repositories/chat_repository.dart';
import '../repositories/message_repository.dart';
import 'theme/theme_cubit.dart';
import 'connectivity/connectivity_cubit.dart';
import 'update/update_cubit.dart';

class AppProviders extends StatelessWidget {
  final Widget child;
  final ConnectivityService connectivity;
  final GemmaService gemmaService;
  final GroqService groqService;
  final OpenRouterService openRouterService;
  final PollinationsService pollinationsService;
  final HuggingFaceImageService huggingFaceImageService;
  final OfflineAIService offlineAIService;
  final OnlineAIService onlineAIService;
  final ModelDownloadService modelDownloadService;
  final AIService aiService;
  final ChatRepository chatRepository;
  final MessageRepository messageRepository;
  final SyncService syncService;

  const AppProviders({
    super.key,
    required this.child,
    required this.connectivity,
    required this.gemmaService,
    required this.groqService,
    required this.openRouterService,
    required this.pollinationsService,
    required this.huggingFaceImageService,
    required this.offlineAIService,
    required this.onlineAIService,
    required this.modelDownloadService,
    required this.aiService,
    required this.chatRepository,
    required this.messageRepository,
    required this.syncService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [..._serviceProviders, ..._blocProviders],
      child: child,
    );
  }

  List<SingleChildWidget> get _serviceProviders => [
    Provider.value(value: connectivity),
    ChangeNotifierProvider.value(value: gemmaService),
    Provider.value(value: groqService),
    Provider.value(value: openRouterService),
    Provider.value(value: pollinationsService),
    Provider.value(value: huggingFaceImageService),
    Provider.value(value: offlineAIService),
    ChangeNotifierProvider.value(value: onlineAIService),
    ChangeNotifierProvider.value(value: modelDownloadService),
    Provider(create: (ctx) => aiService),
    Provider.value(value: chatRepository),
    Provider.value(value: messageRepository),
    Provider.value(value: syncService),
  ];

  List<SingleChildWidget> get _blocProviders => [
    BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
    BlocProvider<ConnectivityCubit>(
      create: (_) => ConnectivityCubit(connectivity),
    ),
    BlocProvider<UpdateCubit>(create: (_) => UpdateCubit()),
  ];
}
