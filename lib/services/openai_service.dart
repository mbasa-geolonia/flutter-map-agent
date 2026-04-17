import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/map_config.dart';
import 'ai_service.dart';
import 'mcp_service.dart';

class OpenAiService implements AiService {
  static const _apiUrl = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o';
  static const String _apiKey = AppConfig.openAiApiKey;

  final McpService? _mcp;
  final List<Map<String, dynamic>> _history = [];

  OpenAiService({McpService? mcp}) : _mcp = mcp;

  static const _systemPrompt =
      'You are a geography and map assistant. When the user asks about a place, '
      'location, route, or geographic topic, use any available geolocation tools '
      '(e.g. geocode, route_search) to look up accurate coordinates first, then '
      'ALWAYS call the show_map function to update the map panel. After showing '
      'the map, provide a helpful and concise explanation. '
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

  /// Build the full tool list: show_map (local) + any MCP tools.
  List<Map<String, dynamic>> _buildTools() => [
        _showMapTool,
        if (_mcp != null) ..._mcp.toOpenAiTools(),
      ];

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
      final tools = _buildTools();
      String textAccumulator = '';

      // Loop until GPT stops requesting tool calls.
      // This supports multi-step flows such as:
      //   1. GPT calls geocode (MCP) → gets coordinates
      //   2. GPT calls show_map (local) → map updates
      //   3. GPT returns final text → done
      while (true) {
        final responseBody = await _callApi(tools);
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final choice =
            (decoded['choices'] as List).first as Map<String, dynamic>;
        final message = choice['message'] as Map<String, dynamic>;
        final finishReason = choice['finish_reason'] as String;

        textAccumulator += message['content'] as String? ?? '';

        // Append assistant message (includes tool_calls if present)
        _history.add(message);

        if (finishReason != 'tool_calls') break;

        // Dispatch every tool call in this turn
        final toolCalls = (message['tool_calls'] as List?) ?? [];
        for (final toolCall in toolCalls) {
          final tc = toolCall as Map<String, dynamic>;
          final fn = tc['function'] as Map<String, dynamic>;
          final name = fn['name'] as String;
          // OpenAI returns arguments as a JSON string — decode it
          final toolInput =
              jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
          final toolCallId = tc['id'] as String;

          final String result;
          if (name == 'show_map') {
            // Local tool — update the map UI directly
            final mapConfig = MapConfig.fromToolInput(toolInput);
            onMap(mapConfig);
            result =
                'Map updated to show: ${mapConfig.title ?? "the requested location"}';
          } else if (_mcp != null && _mcp.hasTool(name)) {
            // MCP tool — forward to the MCP server
            result = await _mcp.callTool(name, toolInput);
          } else {
            result = 'Tool "$name" is not available.';
          }

          // OpenAI expects role: "tool" with matching tool_call_id
          _history.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': result,
          });
        }
      }

      onText(textAccumulator.trim());
      onDone();
    } on http.ClientException catch (e) {
      onError('Network error: ${e.message}');
    } catch (e) {
      onError('$e');
    }
  }

  Future<String> _callApi(List<Map<String, dynamic>> tools) async {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ..._history,
    ];

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 4096,
      'tools': tools,
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
