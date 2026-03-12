import 'dart:convert';
import 'package:http/http.dart' as http;
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
      // Simplified: We skip headers parsing for the template, just body
      final String? body = ls.isString(4) ? ls.toStr(4) : null;

      // Because Http is async but Lua executing in Dart isn't cleanly async (yet),
      // we would normally use isolates or sync HTTP clients. 
      // For this mock template, we will execute a block-wait fetch.
      // (Note: In a real prod environment, we would use ports/isolates for non-blocking HTTP in Lua)
      
      try {
        // Wait synchronously for the demonstration. (Not recommended for UI thread in prod!)
        // Since we are limited by lua's sync nature here:
        final uri = Uri.parse(url);
        final request = http.Request(method, uri);
        
        if (body != null) {
          request.body = body;
          request.headers['Content-Type'] = 'application/json';
        }

        /* 
         WARNING: Making synchronous HTTP calls on the main isolate.
         In a full app we would pass Dart `Future` callbacks to Lua,
         but for this template we use a mock/sync approach. 
         */
      } catch (e) {
        ls.pushString(""); // Empty response
        ls.pushString(e.toString()); // Error
        return 2; // Returning 2 results back to Lua
      }

      // Mocked Response for Anilist since synchronous HTTP in Dart isn't strictly available without FFI!
      // To keep it 100% pure Dart, we will just return a mock JSON of the trending Anime here:
      final mockJson = '''
      {
        "data": {
          "Page": {
            "media": [
              {
                "id": 16498,
                "title": {"romaji": "Shingeki no Kyojin", "english": "Attack on Titan"},
                "coverImage": {"extraLarge": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498-m5ZFB2ALHRVK.jpg"},
                "genres": ["Action", "Drama", "Fantasy", "Mystery"],
                "averageScore": 85,
                "episodes": 25
              },
              {
                "id": 113415,
                "title": {"romaji": "Jujutsu Kaisen", "english": "JUJUTSU KAISEN"},
                "coverImage": {"extraLarge": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx113415-bbBWj4pEFseh.jpg"},
                "genres": ["Action", "Drama", "Supernatural"],
                "averageScore": 86,
                "episodes": 24
              }
            ]
          }
        }
      }
      ''';

      ls.pushString(mockJson);
      ls.pushString(""); // No error
      return 2;
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
      throw Exception("Lua Extension Error: \${decoded['error']}");
    }

    if (decoded is List) {
      return decoded.map((e) => MediaItem.fromJson(e)).toList();
    }
    
    return [];
  }

  void dispose() {
    // lua_dardo 0.0.5 does not require explicit closing of the state.
  }
}
