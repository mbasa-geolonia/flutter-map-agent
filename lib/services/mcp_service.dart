import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A single MCP tool descriptor returned by tools/list.
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

/// MCP client for the Streamable HTTP transport (JSON-RPC 2.0 over HTTP POST).
///
/// Implements the 2024-11-05 MCP protocol:
///   1. POST initialize        → negotiate session, receive Mcp-Session-Id header
///   2. POST notifications/initialized → acknowledge (fire-and-forget)
///   3. POST tools/list        → discover available tools
///   4. POST tools/call        → execute a tool and get results
///
/// The server may respond with either application/json or text/event-stream
/// (SSE); both formats are handled transparently.
class McpService {
  final String serverUrl;

  String? _sessionId;
  List<McpTool> _tools = const [];
  int _nextId = 1;

  McpService({required this.serverUrl});

  /// True after [initialize] completes successfully.
  bool get isReady => _sessionId != null;

  /// Available MCP tools (populated by [initialize]).
  List<McpTool> get tools => _tools;

  /// Returns true if a tool named [name] was discovered.
  bool hasTool(String name) => _tools.any((t) => t.name == name);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Step 1 & 2: Negotiate a session, then step 3: load the tool list.
  Future<void> initialize() async {
    // Step 1 — initialize
    final initResult = await _rpc('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'flutter-map-agent', 'version': '1.0.0'},
    });
    debugPrint('[MCP] Connected – server protocol: '
        '${initResult['protocolVersion'] ?? 'unknown'}');

    // Step 2 — notifications/initialized (notification: no id, 202 response)
    await _notify('notifications/initialized', {});

    // Step 3 — tools/list
    final listResult = await _rpc('tools/list', {});
    final rawTools = (listResult['tools'] as List?) ?? [];

    _tools = rawTools.map((dynamic t) {
      final m = t as Map<String, dynamic>;
      return McpTool(
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
        inputSchema: (m['inputSchema'] as Map<String, dynamic>?) ??
            {'type': 'object', 'properties': {}},
      );
    }).toList();

    debugPrint('[MCP] ${_tools.length} tool(s) loaded: '
        '${_tools.map((t) => t.name).join(', ')}');
  }

  // ── Tool execution ────────────────────────────────────────────────────────

  /// Step 4: Execute the tool named [name] with [arguments].
  /// Returns all text-type content blocks joined with newlines.
  Future<String> callTool(
      String name, Map<String, dynamic> arguments) async {
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });

    final content = (result['content'] as List?) ?? [];
    final parts = content
        .whereType<Map<String, dynamic>>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .toList();

    return parts.join('\n');
  }

  // ── Format converters ─────────────────────────────────────────────────────

  /// Convert MCP tools to Anthropic Claude's format (uses `input_schema`).
  List<Map<String, dynamic>> toClaudeTools() => _tools
      .map((t) => {
            'name': t.name,
            'description': t.description,
            'input_schema': t.inputSchema,
          })
      .toList();

  /// Convert MCP tools to OpenAI's function-calling format (uses `parameters`).
  List<Map<String, dynamic>> toOpenAiTools() => _tools
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            },
          })
      .toList();

  // ── Private JSON-RPC helpers ──────────────────────────────────────────────

  /// Send a JSON-RPC request and return the `result` field.
  Future<Map<String, dynamic>> _rpc(
      String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final response = await _post({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': id,
    });

    if (response.bodyBytes.isEmpty) return {};

    final decoded = _decodeBody(response);
    if (decoded.containsKey('error')) {
      throw Exception('[MCP] RPC error for "$method": ${decoded['error']}');
    }
    return (decoded['result'] as Map<String, dynamic>?) ?? {};
  }

  /// Send a JSON-RPC notification (no `id` — server returns 202, no body).
  Future<void> _notify(String method, Map<String, dynamic> params) async {
    await _post({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  Future<http.Response> _post(Map<String, dynamic> body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      // Accept both plain JSON and SSE — server picks the format
      'Accept': 'application/json, text/event-stream',
    };
    if (_sessionId != null) headers['Mcp-Session-Id'] = _sessionId!;

    final response = await http.post(
      Uri.parse(serverUrl),
      headers: headers,
      body: jsonEncode(body),
    );

    // Capture session ID whenever the server sends it
    final sid = response.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _sessionId = sid;

    // 202 Accepted is the expected response for notifications
    if (response.statusCode == 202) return response;

    if (response.statusCode != 200) {
      throw Exception(
          '[MCP] HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }
    return response;
  }

  /// Decode either a plain `application/json` body or the first SSE `data:` line.
  ///
  /// Uses `bodyBytes` decoded explicitly as UTF-8, NOT `response.body` — the
  /// MCP server's `text/event-stream` responses have no `charset` parameter
  /// in their Content-Type, and `http.Response.body` silently falls back to
  /// Latin-1 in that case, corrupting every multi-byte character (e.g.
  /// Japanese text) into mojibake.
  Map<String, dynamic> _decodeBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    final body = utf8.decode(response.bodyBytes).trim();

    if (contentType.contains('text/event-stream')) {
      for (final line in body.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('data:')) {
          final data = trimmed.substring(5).trim();
          if (data.isNotEmpty && data != '[DONE]') {
            return jsonDecode(data) as Map<String, dynamic>;
          }
        }
      }
      throw const FormatException('[MCP] No data line found in SSE response');
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }
}
