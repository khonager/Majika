import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local decisions, independent of imported service profiles.
class MediaLibrary extends ChangeNotifier {
  static const storageKey = 'library.decisions.v1';
  Map<String, MediaItem> _saved = {};
  Map<String, MediaItem> _hidden = {};
  Future<void> _pendingWrite = Future<void>.value();

  List<MediaItem> get saved => _saved.values.toList().reversed.toList();
  List<MediaItem> get hidden => _hidden.values.toList().reversed.toList();
  bool isSaved(MediaItem item) => _saved.containsKey(item.id);
  bool isHidden(MediaItem item) => _hidden.containsKey(item.id);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map;
      _saved = _readItems(json['saved']);
      _hidden = _readItems(json['hidden']);
    } catch (_) {
      // A malformed cache should never prevent the app from opening.
    }
  }

  Map<String, MediaItem> _readItems(Object? value) {
    final result = <String, MediaItem>{};
    if (value is! List) return result;
    for (final entry in value) {
      try {
        final item = MediaItem.fromJson(
          Map<String, dynamic>.from(entry as Map),
        );
        if (item.id.isNotEmpty) result[item.id] = item;
      } catch (_) {
        // Keep the rest of the list when a single item is damaged.
      }
    }
    return result;
  }

  Future<void> toggleSaved(MediaItem item) => _change(() {
    if (_saved.remove(item.id) == null) {
      _saved[item.id] = item;
      _hidden.remove(item.id);
    }
  });

  Future<void> setHidden(MediaItem item, bool hidden) => _change(() {
    if (hidden) {
      _hidden[item.id] = item;
    } else {
      _hidden.remove(item.id);
    }
  });

  // Commit only after storage succeeds. Failed writes leave the visible state
  // unchanged; a failed operation does not block later attempts.
  Future<void> _change(VoidCallback change) {
    final result = _pendingWrite.then((_) async {
      final oldSaved = Map<String, MediaItem>.of(_saved);
      final oldHidden = Map<String, MediaItem>.of(_hidden);
      change();
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = await prefs.setString(
          storageKey,
          jsonEncode({
            'saved': _saved.values.map((item) => item.toJson()).toList(),
            'hidden': _hidden.values.map((item) => item.toJson()).toList(),
          }),
        );
        if (!saved)
          throw StateError('Could not save your list on this device.');
      } catch (_) {
        _saved = oldSaved;
        _hidden = oldHidden;
        rethrow;
      }
      notifyListeners();
    });
    _pendingWrite = result.catchError((Object _) {});
    return result;
  }
}
