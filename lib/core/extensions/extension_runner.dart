import 'dart:convert';
import 'package:lua_dardo/lua.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/models/media_item.dart';

class ExtensionRunner {
  late LuaState _ls;
  bool _isReady = false;

  ExtensionRunner() {
    _initEngine();
  }

  void _initEngine() {
    // Open a new Lua State
    _ls = LuaState.newState();

    // Load standard Lua libraries (math, string, table, etc.)
    _ls.openLibs();

    _injectCoreApi();
    _isReady = true;
  }

  /// Injects the `MajikaHttp` function into the global Lua instance so it can make network calls
  void _injectCoreApi() {
    // Return a request descriptor to Lua. The actual HTTPS request runs later
    // in async Dart code so we can use a proper TLS-capable client.
    _ls.pushDartFunction((LuaState ls) {
      final String method = ls.checkString(1) ?? 'GET';
      final String url = ls.checkString(2) ?? '';

      // We accept the raw graphql query as argument 4, and the page variable as argument 5
      final String? queryText = ls.isString(4) ? ls.toStr(4) : null;
      final String? pageVar = ls.isString(5) ? ls.toStr(5) : null;

      try {
        final Map<String, dynamic> requestSpec = {
          'request': {
            'method': method,
            'url': url,
            if (queryText != null && queryText.isNotEmpty) 'query': queryText,
            if (pageVar != null)
              'variables': {'page': int.tryParse(pageVar) ?? 1, 'perPage': 20},
          },
        };

        ls.pushString(jsonEncode(requestSpec));
        ls.pushString("");
        return 2;
      } catch (e) {
        ls.pushString("");
        ls.pushString(e.toString());
        return 2;
      }
    });

    // Set the global variable standard name
    _ls.setGlobal('MajikaHttp');
  }

  /// Loads an extension Lua file text into the engine
  void loadExtension(String extensionCode) {
    if (!_isReady) _initEngine();

    // Load the script text
    final ThreadStatus loadStatus = _ls.loadString(extensionCode);
    if (loadStatus != ThreadStatus.luaOk) {
      final errorMsg = _ls.toStr(-1);
      _ls.pop(1);
      throw Exception('Lua Syntax Error: $errorMsg');
    }

    // Execute the loaded script (pcall with 0 args, 1 return value expected: the table)
    final ThreadStatus runStatus = _ls.pCall(0, 1, 0);
    if (runStatus != ThreadStatus.luaOk) {
      final errorMsg = _ls.toStr(-1);
      _ls.pop(1);
      throw Exception('Lua Runtime Error: $errorMsg');
    }

    // The script `returns` a table at the end with its functions.
    // We store this table reference in the global namespace.
    _ls.setGlobal('ActiveExtension');
  }

  /// Executes the `fetchDiscoverFeed` function defined in the loaded Lua extension
  Future<List<MediaItem>> runFetchDiscoverFeed({int page = 1}) async {
    // Get the global table
    _ls.getGlobal('ActiveExtension'); // Push table to stack

    // Push the function key we want to call
    _ls.pushString('fetchDiscoverFeed');

    // Get the function from the table
    _ls.getTable(-2);

    // Provide arguments
    _ls.pushInteger(page);

    // Call the function (1 argument, 1 result)
    _ls.call(1, 1);

    // Read the returned JSON string
    final resultString = _ls.toStr(-1);
    _ls.pop(1); // Clean up stack

    if (resultString == null || resultString.isEmpty) {
      return [];
    }

    final dynamic decoded = jsonDecode(resultString);

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception("Lua Extension Error: ${decoded['error']}");
    }

    final resolved = await _resolveExtensionResponse(decoded);

    // Since lua_dardo has no native JSON parser, the Lua script returns either
    // a request descriptor or the raw GraphQL JSON string.
    if (resolved is Map && resolved.containsKey('data')) {
      final List mediaList = resolved['data']['Page']['media'];

      return mediaList.map((media) {
        final title = media['title']['english'] ?? media['title']['romaji'];
        final rating = media['averageScore'] != null
            ? (media['averageScore'] / 10).toDouble()
            : null;
        final subtitle = media['episodes'] != null
            ? "${media['episodes']} Episodes"
            : "";

        return MediaItem(
          id: "anilist_${media['id']}",
          title: title,
          coverUrl: media['coverImage']['extraLarge'],
          tags: List<String>.from(media['genres'] ?? []),
          rating: rating,
          subtitle: subtitle,
          extensionId: "com.majika.ext.anilist",
        );
      }).toList();
    }

    return [];
  }

  Future<dynamic> _resolveExtensionResponse(dynamic decoded) async {
    if (decoded is! Map || !decoded.containsKey('request')) {
      return decoded;
    }

    final dynamic rawRequest = decoded['request'];
    if (rawRequest is! Map) {
      throw Exception('Lua Extension Error: Invalid request descriptor');
    }

    final String method = (rawRequest['method'] as String? ?? 'GET')
        .toUpperCase();
    final String? url = rawRequest['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Lua Extension Error: Missing request URL');
    }

    final Uri uri = Uri.parse(url);
    final Map<String, dynamic> body = {
      if (rawRequest['query'] != null) 'query': rawRequest['query'],
      if (rawRequest['variables'] != null) 'variables': rawRequest['variables'],
    };

    late final http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'Majika/1.0',
          },
          body: jsonEncode(body),
        );
        break;
      default:
        throw Exception('Lua Extension Error: Unsupported HTTP method $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Lua Extension Error: HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body);
  }

  void dispose() {
    // lua_dardo 0.0.5 does not require explicit closing of the state.
  }
}
