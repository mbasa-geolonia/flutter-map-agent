import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/map_config.dart';
import '../services/claude_service.dart';
import '../widgets/chat_panel.dart';
import '../widgets/map_panel.dart';

class AppState extends ChangeNotifier {
  final _claudeService = ClaudeService();
  final List<ChatMessage> messages = [];
  MapConfig mapConfig = MapConfig.defaultConfig;
  bool isLoading = false;

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isLoading) return;

    final userMsg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_user',
      role: MessageRole.user,
      text: text,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);

    final assistantId = '${DateTime.now().millisecondsSinceEpoch}_assistant';
    messages.add(ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      text: '',
      timestamp: DateTime.now(),
      isLoading: true,
    ));

    isLoading = true;
    notifyListeners();

    await _claudeService.sendMessage(
      userText: text,
      onText: (responseText) {
        final idx = messages.indexWhere((m) => m.id == assistantId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            text: responseText,
            isLoading: false,
          );
        }
        notifyListeners();
      },
      onMap: (config) {
        mapConfig = config;
        notifyListeners();
      },
      onDone: () {
        isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        final idx = messages.indexWhere((m) => m.id == assistantId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            text: 'Error: $error',
            isLoading: false,
          );
        }
        isLoading = false;
        notifyListeners();
      },
    );
  }

  void clearConversation() {
    messages.clear();
    _claudeService.clearHistory();
    mapConfig = MapConfig.defaultConfig;
    notifyListeners();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody();

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  double _chatWidth = 380;
  static const double _minChatWidth = 280;
  static const double _maxChatWidth = 600;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _chatWidth,
            child: const ChatPanel(),
          ),
          // Draggable divider
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              setState(() {
                _chatWidth = (_chatWidth + details.delta.dx).clamp(
                  _minChatWidth,
                  _maxChatWidth,
                );
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 6,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
          ),
          const Expanded(child: MapPanel()),
        ],
      ),
    );
  }
}
