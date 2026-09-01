import 'dart:async';
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
      'call the show_map function to update the map panel. After showing '
      'the map, provide a helpful and concise explanation. '
      'For cities, use zoom 10-12. For streets/buildings, use zoom 15-18. '
      'For countries/continents, use zoom 4-7. Always show the map first. '
      'When a tool result says "GeoJSON rendered" or "CSV/WKT rendered", the '
      'geometry is already displayed with default colors. You may call '
      'show_map once to add markers or set polygon_fill_color — do NOT '
      'include a polygons or routes array, as the coordinates are already '
      'rendered and will be preserved automatically.';

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
                'popup_info': {
                  'type': 'string',
                  'description':
                      'Informational text shown in a popup when the user taps '
                      'this polygon. Include relevant details such as area name, '
                      'statistics, descriptions, or any other useful information.',
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
          'polygon_fill_color': {
            'type': 'string',
            'description':
                'Override the fill color of ALL polygons already on the map, '
                'including any auto-rendered GeoJSON isochrones or areas. '
                'Use this when the user requests a specific color for an area '
                'that was drawn by a previous tool call. Value is #RRGGBB hex '
                '(e.g. "#43A047" for green).',
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

      // Tracks GeoJSON-rendered map state so subsequent show_map calls
      // (e.g. adding Start/End markers) merge with existing routes/polygons
      // rather than replacing them.
      MapConfig? accumulatedMapConfig;
      // Number of polygons/routes added by the most recent GeoJSON render.
      // polygon_fill_color applies only to these, not all accumulated features.
      int lastGeoJsonPolygonCount = 0;
      int lastGeoJsonRouteCount = 0;

      // Merges an auto-rendered config (from GeoJSON or CSV+WKT) into the
      // accumulated map state, updates the fill-color-override bookkeeping,
      // and pushes the result to the UI.
      MapConfig mergeAutoRendered(MapConfig autoConfig) {
        final current = accumulatedMapConfig;
        final merged = current == null
            ? autoConfig
            : MapConfig(
                centerLat: autoConfig.centerLat,
                centerLng: autoConfig.centerLng,
                zoom: autoConfig.zoom,
                title: autoConfig.title ?? current.title,
                markers: [...current.markers, ...autoConfig.markers],
                routes: [...current.routes, ...autoConfig.routes],
                polygons: [...current.polygons, ...autoConfig.polygons],
                circles: [...current.circles, ...autoConfig.circles],
              );
        lastGeoJsonPolygonCount = autoConfig.polygons.length;
        lastGeoJsonRouteCount = autoConfig.routes.length;
        accumulatedMapConfig = merged;
        onMap(merged);
        return merged;
      }

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
            // Local tool — update the map UI directly.
            // Merge with any previously GeoJSON-rendered features so that
            // routes/polygons aren't wiped when Claude adds markers on top.
            // polygon_fill_color applies only to the polygons/routes added by
            // the most recent GeoJSON render, not all accumulated features.
            final fromTool = MapConfig.fromToolInput(toolInput);
            final polygonFillOverride =
                toolInput['polygon_fill_color'] as String?;
            final MapConfig mapConfig;
            if (accumulatedMapConfig == null) {
              mapConfig = fromTool;
            } else {
              // Closures over `accumulatedMapConfig` elsewhere in this scope
              // disable null-promotion, so bind a definitely-non-null local.
              final current = accumulatedMapConfig!;
              List<MapPolygon> mergedPolygons;
              if (polygonFillOverride != null && lastGeoJsonPolygonCount > 0) {
                final total = current.polygons.length;
                final splitAt = (total - lastGeoJsonPolygonCount).clamp(0, total);
                mergedPolygons = [
                  ...current.polygons.sublist(0, splitAt),
                  ...current.polygons.sublist(splitAt).map((p) =>
                      MapPolygon(
                        points: p.points,
                        label: p.label,
                        fillColor: polygonFillOverride,
                        popupInfo: p.popupInfo,
                      )),
                  ...fromTool.polygons,
                ];
              } else {
                mergedPolygons = [
                  ...current.polygons,
                  ...fromTool.polygons,
                ];
              }
              mapConfig = MapConfig(
                centerLat: fromTool.centerLat,
                centerLng: fromTool.centerLng,
                zoom: fromTool.zoom,
                title: fromTool.title ?? current.title,
                markers: [
                  ...current.markers,
                  ...fromTool.markers,
                ],
                routes: [
                  ...current.routes,
                  ...fromTool.routes,
                ],
                polygons: mergedPolygons,
                circles: [
                  ...current.circles,
                  ...fromTool.circles,
                ],
              );
            }
            lastGeoJsonPolygonCount = 0;
            lastGeoJsonRouteCount = 0;
            accumulatedMapConfig = mapConfig;
            onMap(mapConfig);
            result =
                'Map updated to show: ${mapConfig.title ?? "the requested location"}';
          } else if (_mcp != null && _mcp.hasTool(name)) {
            // MCP tool — forward to the MCP server
            final rawResult = await _mcp.callTool(name, toolInput);

            // If the MCP result is GeoJSON or CSV+WKT, render it directly
            // rather than asking the model to re-emit thousands of coordinates.
            String mcpResult = rawResult;
            MapConfig? autoConfig;
            String sourceLabel = 'GeoJSON';
            try {
              final decoded = jsonDecode(rawResult);
              if (decoded is Map<String, dynamic> &&
                  MapConfig.isGeoJson(decoded)) {
                autoConfig = MapConfig.fromGeoJson(
                  decoded,
                  title: name.replaceAll('_', ' '),
                  paletteOffset: (accumulatedMapConfig?.routes.length ?? 0) +
                      (accumulatedMapConfig?.polygons.length ?? 0),
                );
              }
            } catch (_) {}
            if (autoConfig == null && MapConfig.looksLikeCsvWkt(rawResult)) {
              sourceLabel = 'CSV/WKT';
              autoConfig = MapConfig.fromCsvWkt(
                rawResult,
                title: name.replaceAll('_', ' '),
                paletteOffset: (accumulatedMapConfig?.routes.length ?? 0) +
                    (accumulatedMapConfig?.polygons.length ?? 0),
              );
            }
            if (autoConfig != null) {
              final hasData = autoConfig.markers.isNotEmpty ||
                  autoConfig.routes.isNotEmpty ||
                  autoConfig.polygons.isNotEmpty;
              if (hasData) {
                final newColors = autoConfig.polygons
                    .map((p) => p.fillColor ?? 'default')
                    .join(', ');
                final merged = mergeAutoRendered(autoConfig);
                mcpResult =
                    '$sourceLabel rendered: ${autoConfig.polygons.length} new '
                    'polygon(s) with auto-assigned color(s): [$newColors]. '
                    'Total on map: ${merged.polygons.length} polygon(s), '
                    '${merged.routes.length} route(s). '
                    'To change the color of these new polygon(s), call '
                    'show_map with polygon_fill_color. To add markers, '
                    'include them in show_map. '
                    'Do NOT include polygon or route coordinates.';
              }
            }
            result = mcpResult;
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
    } on TimeoutException {
      onError('Request timed out. Please try again.');
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
      'max_tokens': 8192,
      'tools': tools,
      'messages': messages,
    });

    final response = await http
        .post(
          Uri.parse(_apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
    return response.body;
  }

  @override
  void clearHistory() => _history.clear();
}
