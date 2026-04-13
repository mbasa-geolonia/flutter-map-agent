import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/map_config.dart';
import 'ai_service.dart';

class OpenAiService implements AiService {
  static const _apiUrl = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o';
  static const String _apiKey = AppConfig.openAiApiKey;

  final List<Map<String, dynamic>> _history = [];

  static const _systemPrompt =
      'You are a geography and map assistant. When the user asks about a place, '
      'location, route, or geographic topic, ALWAYS call the show_map function to '
      'update the map panel. After calling the function, provide a helpful and '
      'concise explanation of the location. Use accurate coordinates. '
      'For cities, use zoom 10-12. For streets/buildings, use zoom 15-18. '
      'For countries/continents, use zoom 4-7. Always show the map first.';

  // OpenAI tool definition: uses "function" wrapper and "parameters" (not "input_schema")
  static const _showMapTool = {
    'type': 'function',
    'function': {
      'name': 'show_map',
      'description':
          'Update the interactive map panel to show a specific location with '
          'optional markers, polygons, and routes. Call this whenever any '
          'geographic visualization would help the user understand a location.',
      'parameters': {
        'type': 'object',
        'properties': {
          'center_lat': {
            'type': 'number',
            'description': 'Latitude of the map center (-90 to 90)',
          },
          'center_lng': {
            'type': 'number',
            'description': 'Longitude of the map center (-180 to 180)',
          },
          'zoom': {
            'type': 'number',
            'description':
                'Zoom level: 1=world, 4=continent, 7=country, 10=city, 13=district, 15=street, 18=building',
          },
          'title': {
            'type': 'string',
            'description': 'Title shown in the map panel header',
          },
          'markers': {
            'type': 'array',
            'description': 'Points of interest to pin on the map',
            'items': {
              'type': 'object',
              'properties': {
                'lat': {'type': 'number', 'description': 'Latitude'},
                'lng': {'type': 'number', 'description': 'Longitude'},
                'label': {
                  'type': 'string',
                  'description': 'Text label shown on the pin',
                },
              },
              'required': ['lat', 'lng', 'label'],
            },
          },
          'polygons': {
            'type': 'array',
            'description': 'Filled polygon shapes for regions, districts, or areas',
            'items': {
              'type': 'object',
              'properties': {
                'points': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'lat': {'type': 'number'},
                      'lng': {'type': 'number'},
                    },
                    'required': ['lat', 'lng'],
                  },
                },
                'label': {'type': 'string'},
              },
              'required': ['points'],
            },
          },
          'routes': {
            'type': 'array',
            'description': 'Polyline paths or routes between locations',
            'items': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'lat': {'type': 'number'},
                  'lng': {'type': 'number'},
                },
                'required': ['lat', 'lng'],
              },
            },
          },
        },
        'required': ['center_lat', 'center_lng'],
      },
    },
  };

  @override
  Future<void> sendMessage({
    required String userText,
    required OnTextCallback onText,
    required OnMapCallback onMap,
    required OnDoneCallback onDone,
    required OnErrorCallback onError,
  }) async {
    _history.add({'role': 'user', 'content': userText});

    try {
      final responseBody = await _callApi();
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final choice = (decoded['choices'] as List).first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      final finishReason = choice['finish_reason'] as String;

      String textAccumulator = message['content'] as String? ?? '';
      final toolCalls = message['tool_calls'] as List?;

      // Append assistant message to history
      _history.add({'role': 'assistant', 'content': message});

      if (finishReason == 'tool_calls' && toolCalls != null) {
        for (final toolCall in toolCalls) {
          final tc = toolCall as Map<String, dynamic>;
          final fn = tc['function'] as Map<String, dynamic>;

          if (fn['name'] == 'show_map') {
            // OpenAI returns arguments as a JSON string — decode it
            final toolInput =
                jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
            final toolCallId = tc['id'] as String;

            final mapConfig = MapConfig.fromToolInput(toolInput);
            onMap(mapConfig);

            // Send tool result back with role: "tool"
            _history.add({
              'role': 'tool',
              'tool_call_id': toolCallId,
              'content':
                  'Map updated to show: ${mapConfig.title ?? "the requested location"}',
            });
          }
        }

        // Second call to get the text response after tool execution
        final responseBody2 = await _callApi();
        final decoded2 =
            jsonDecode(responseBody2) as Map<String, dynamic>;
        final choice2 =
            (decoded2['choices'] as List).first as Map<String, dynamic>;
        final message2 = choice2['message'] as Map<String, dynamic>;

        textAccumulator += message2['content'] as String? ?? '';
        _history.add({'role': 'assistant', 'content': message2});
      }

      onText(textAccumulator.trim());
      onDone();
    } on http.ClientException catch (e) {
      onError('Network error: ${e.message}');
    } catch (e) {
      onError('$e');
    }
  }

  Future<String> _callApi() async {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ..._history,
    ];

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 4096,
      'tools': [_showMapTool],
      'messages': messages,
    });

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
    return response.body;
  }

  @override
  void clearHistory() => _history.clear();
}
