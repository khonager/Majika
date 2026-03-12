import 'dart:convert';
import 'package:sync_http/sync_http.dart';
import 'package:lua_dardo/lua.dart'; 
import 'package:lua_dardo/src/api/lua_type.dart';
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
    // Register the Dart closure into the Lua C-function format
    _ls.pushDartFunction((LuaState ls) {
      final String method = ls.checkString(1) ?? 'GET';
      final String url = ls.checkString(2) ?? '';
      
      // We accept the raw graphql query as argument 4, and the page variable as argument 5
      final String? queryText = ls.isString(4) ? ls.toStr(4) : null;
      final String? pageVar = ls.isString(5) ? ls.toStr(5) : null;
      
      String? bodyStr;
      
      if (queryText != null && queryText.isNotEmpty) {
        // Build the GraphQL JSON body natively in Dart so it's guaranteed perfectly formatted
        final Map<String, dynamic> graphqlBody = {
          "query": queryText,
        };
        
        if (pageVar != null) {
          graphqlBody["variables"] = {
            "page": int.tryParse(pageVar) ?? 1,
            "perPage": 20
          };
        }
        bodyStr = jsonEncode(graphqlBody);
      }

      try {
        final uri = Uri.parse(url);
        
        final req = SyncHttpClient.postUrl(uri);
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Accept', 'application/json');
        req.headers.set('User-Agent', 'MajikaApp/1.0 (Linux; Desktop)');
        
        if (bodyStr != null) {
          final bodyBytes = utf8.encode(bodyStr);
          req.headers.set('Content-Length', bodyBytes.length.toString());
          req.write(bodyStr);
        }

        final res = req.close();
        final responseBody = res.body ?? "";

        if (res.statusCode != 200) {
          ls.pushString(""); // Empty response
          final safeErr = jsonEncode("HTTP ${res.statusCode}: $responseBody");
          ls.pushString(safeErr.substring(1, safeErr.length - 1)); // Strip the quotes added by jsonEncode so Lua can build its own json string
          return 2;
        }

        ls.pushString(responseBody); // Success response
        ls.pushString(""); // No Error
        return 2;

      } catch (e) {
        ls.pushString(""); // Empty response
        ls.pushString(e.toString()); // Error
        return 2; // Returning 2 results back to Lua
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
      throw Exception("Lua Syntax Error: \$errorMsg");
    }

    // Execute the loaded script (pcall with 0 args, 1 return value expected: the table)
    final ThreadStatus runStatus = _ls.pCall(0, 1, 0);
    if (runStatus != ThreadStatus.luaOk) {
      final errorMsg = _ls.toStr(-1);
      _ls.pop(1);
      throw Exception("Lua Runtime Error: \$errorMsg");
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

    // Since lua_dardo has no native JSON parser, the Lua script returns 
    // the raw GraphQL JSON string. We parse the Anilist structure here.
    if (decoded is Map && decoded.containsKey('data')) {
      final List mediaList = decoded['data']['Page']['media'];
      
      return mediaList.map((media) {
        final title = media['title']['english'] ?? media['title']['romaji'];
        final rating = media['averageScore'] != null ? (media['averageScore'] / 10).toDouble() : null;
        final subtitle = media['episodes'] != null ? "\${media['episodes']} Episodes" : "";
        
        return MediaItem(
          id: "anilist_\${media['id']}",
          title: title,
          coverUrl: media['coverImage']['extraLarge'],
          tags: List<String>.from(media['genres'] ?? []),
          rating: rating,
          subtitle: subtitle,
          extensionId: "com.majika.ext.anilist"
        );
      }).toList();
    }
    
    return [];
  }

  void dispose() {
    // lua_dardo 0.0.5 does not require explicit closing of the state.
  }
}
