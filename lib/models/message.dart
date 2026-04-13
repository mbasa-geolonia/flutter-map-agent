enum MessageRole { user, assistant }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String text;
  final DateTime timestamp;
  final bool isLoading;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.isLoading = false,
  });

  ChatMessage copyWith({String? text, bool? isLoading}) => ChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isLoading: isLoading ?? this.isLoading,
      );
}
