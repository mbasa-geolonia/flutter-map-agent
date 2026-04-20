import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/map_config.dart';
import 'ai_service.dart';
import 'mcp_service.dart';

class ClaudeService implements AiService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-4-6';
  static const String _apiKey = AppConfig.anthropicApiKey;

  final McpService? _mcp;
  final List<Map<String, dynamic>> _history = [];

  ClaudeService({McpService? mcp}) : _mcp = mcp;

  static const _systemPrompt =
      'You are a geography and map assistant. When the user asks about a place, '
      'location, route, or geographic topic, use any available geolocation tools '
      '(e.g. geocode, route_search) to look up accurate coordinates first, then '
      'ALWAYS call the show_map tool to update the map panel. After showing the '
      'map, provide a helpful and concise explanation. '
      'For cities, use zoom 10-12. For streets/buildings, use zoom 15-18. '
      'For countries/continents, use zoom 4-7. Always show the map first.';

  static const _showMapTool = {
    'name': 'show_map',
    'description':
        'Update the interactive map panel to show a specific location with '
        'optional markers, polygons, and routes. Call this whenever any '
        'geographic visualization would help the user understand a location.',
    'input_schema': {
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
              'color': {
                'type': 'string',
                'description':
                    'Pin color as #RRGGBB hex (e.g. "#E53935"). '
                    'Use consistent colors per category for thematic maps.',
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
              'fill_color': {
                'type': 'string',
                'description':
                    'Fill color as #RRGGBB hex (e.g. "#FF9800"). '
                    'A semi-transparent fill is applied automatically.',
              },
              'stroke_color': {
                'type': 'string',
                'description':
                    'Border color as #RRGGBB hex. Defaults to fill_color if omitted.',
              },
            },
            'required': ['points'],
          },
        },
        'routes': {
          'type': 'array',
          'description': 'Polyline paths or routes between locations',
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
              'color': {
                'type': 'string',
                'description':
                    'Route stroke color as #RRGGBB hex (e.g. "#43A047").',
              },
            },
            'required': ['points'],
          },
        },
        'circles': {
          'type': 'array',
          'description': 'Radius circles for showing coverage or proximity areas',
          'items': {
            'type': 'object',
            'properties': {
              'lat': {
                'type': 'number',
                'description': 'Center latitude of the circle',
              },
              'lng': {
                'type': 'number',
                'description': 'Center longitude of the circle',
              },
              'radius_m': {
                'type': 'number',
                'description': 'Radius in meters (e.g. 500 for 500 m)',
              },
              'label': {
                'type': 'string',
                'description': 'Optional label for the circle',
              },
              'fill_color': {
                'type': 'string',
                'description':
                    'Fill color as #RRGGBB hex (e.g. "#1E88E5"). '
                    'A semi-transparent fill is applied automatically.',
              },
              'stroke_color': {
                'type': 'string',
                'description':
                    'Border color as #RRGGBB hex. Defaults to fill_color if omitted.',
              },
            },
            'required': ['lat', 'lng', 'radius_m'],
          },
        },
      },
      'required': ['center_lat', 'center_lng'],
    },
  };

  /// Build the full tool list: show_map (local) + any MCP tools.
  List<Map<String, dynamic>> _buildTools() => [
        _showMapTool,
        if (_mcp != null) ..._mcp.toClaudeTools(),
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

      // Loop until Claude stops requesting tool calls.
      // This supports multi-step flows such as:
      //   1. Claude calls geocode (MCP) → gets coordinates
      //   2. Claude calls show_map (local) → map updates
      //   3. Claude returns final text → done
      while (true) {
        final responseBody = await _callApi(tools);
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final stopReason = decoded['stop_reason'] as String;
        final content = decoded['content'] as List;

        for (final block in content) {
          final b = block as Map<String, dynamic>;
          if (b['type'] == 'text') textAccumulator += b['text'] as String;
        }

        // Anthropic requires the full content array to be appended as-is
        _history.add({'role': 'assistant', 'content': content});

        if (stopReason != 'tool_use') break;

        // Dispatch every tool_use block in this turn
        final toolResults = <Map<String, dynamic>>[];
        for (final block in content) {
          final b = block as Map<String, dynamic>;
          if (b['type'] != 'tool_use') continue;

          final name = b['name'] as String;
          final input = b['input'] as Map<String, dynamic>;
          final id = b['id'] as String;

          final String result;
          if (name == 'show_map') {
            // Local tool — update the map UI directly
            final mapConfig = MapConfig.fromToolInput(input);
            onMap(mapConfig);
            result =
                'Map updated to show: ${mapConfig.title ?? "the requested location"}';
          } else if (_mcp != null && _mcp.hasTool(name)) {
            // MCP tool — forward to the MCP server
            result = await _mcp.callTool(name, input);
          } else {
            result = 'Tool "$name" is not available.';
          }

          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'content': result,
          });
        }

        _history.add({'role': 'user', 'content': toolResults});
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
    final body = jsonEncode({
      'model': _model,
      'max_tokens': 4096,
      'system': _systemPrompt,
      'tools': tools,
      'messages': _history,
    });

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
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
