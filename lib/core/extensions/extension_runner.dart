import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/models/media_item.dart';

class ExtensionRunner {
  late JavascriptRuntime _jsRuntime;
  bool _isReady = false;

  // Holds the registered extension functions from the Javascript side
  final Map<String, dynamic> _extensionRegistry = {};

  ExtensionRunner() {
    _initEngine();
  }

  void _initEngine() {
    _jsRuntime = getJavascriptRuntime();
    _injectCoreApi();
    _isReady = true;
  }

  /// Injects the `MajikaHttp` and `MajikaExtension` polyfills into the JS environment.
  /// This allows the untrusted JS code to make network requests through Dart's secure HTTP layer.
  void _injectCoreApi() {
    // 1. HTTP Polyfill
    _jsRuntime.onMessage('MajikaHttp_post', (dynamic args) async {
      try {
        final Map<String, dynamic> params = args;
        final String url = params['url'];
        final Map<String, String>? headers = params['headers'] != null ? Map<String, String>.from(params['headers']) : null;
        final String? body = params['body'];

        final response = await http.post(
          Uri.parse(url),
          headers: headers,
          body: body,
        );
        
        return response.body; // Return string payload to JS
      } catch (e) {
        return jsonEncode({"error": e.toString()});
      }
    });

    // 2. Extension Registry API
    _jsRuntime.evaluate('''
      // Create the Majika global namespaces
      var MajikaExtension = {
        register: function(exports) {
          // Send the exported functions/config back to Dart
          sendMessage('MajikaExtension_register', JSON.stringify(exports.config));
        }
      };

      var MajikaHttp = {
        post: function(url, options) {
          return new Promise(function(resolve, reject) {
            sendMessage('MajikaHttp_post', JSON.stringify({
              url: url,
              headers: options ? options.headers : null,
              body: options ? options.body : null
            })).then(resolve).catch(reject);
          });
        }
      };
    ''');
  }

  /// Loads an extension JS file text into the engine
  Future<void> loadExtension(String extensionCode) async {
    if (!_isReady) _initEngine();

    // The script must call MajikaExtension.register(...) at the end definition.
    _jsRuntime.evaluate(extensionCode);
    
    // Note: In a real app we would capture the 'MajikaExtension_register' event via Dart onMessage,
    // but flutter_js handles Promise/Async boundaries oddly. 
    // To simplify, we simply query the defined JS functions directly from Dart!
  }

  /// Executes the `fetchDiscoverFeed` function defined in the loaded JS extension
  Future<List<MediaItem>> runFetchDiscoverFeed({int page = 1}) async {
    // We execute the JS function and await its promise using flutter_js evaluateAsync
    final result = await _jsRuntime.evaluateAsync('''
      (async function() {
        try {
          var res = await fetchDiscoverFeed($page);
          return JSON.stringify(res);
        } catch(e) {
          return JSON.stringify({error: e.toString()});
        }
      })();
    ''');

    final String resultString = result.stringResult;
    final dynamic decoded = jsonDecode(resultString);

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception("JS Extension Error: \${decoded['error']}");
    }

    // Map the string JSON output back to Dart objects
    if (decoded is List) {
      return decoded.map((e) => MediaItem.fromJson(e)).toList();
    }
    
    return [];
  }

  void dispose() {
    _jsRuntime.dispose();
  }
}
