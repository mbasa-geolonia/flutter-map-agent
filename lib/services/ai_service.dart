import '../models/map_config.dart';

typedef OnTextCallback = void Function(String text);
typedef OnMapCallback = void Function(MapConfig config);
typedef OnDoneCallback = void Function();
typedef OnErrorCallback = void Function(String error);

/// Common interface for AI chat backends (Anthropic Claude, OpenAI, etc.).
abstract interface class AiService {
  Future<void> sendMessage({
    required String userText,
    required OnTextCallback onText,
    required OnMapCallback onMap,
    required OnDoneCallback onDone,
    required OnErrorCallback onError,
  });

  void clearHistory();
}
