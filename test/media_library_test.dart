import 'dart:convert';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/storage/media_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  MediaItem item(String id) =>
      MediaItem(id: id, title: id, coverUrl: '', tags: const []);

  test(
    'saved and hidden decisions survive restart and concurrent updates',
    () async {
      final library = MediaLibrary();
      await library.load();
      await Future.wait([
        library.toggleSaved(item('one')),
        library.toggleSaved(item('two')),
        library.setHidden(item('three'), true),
      ]);
      final restored = MediaLibrary();
      await restored.load();
      expect(restored.saved.map((item) => item.id), ['two', 'one']);
      expect(restored.isHidden(item('three')), isTrue);
      await restored.toggleSaved(item('three'));
      expect(restored.isHidden(item('three')), isFalse);
      await restored.setHidden(item('one'), true);
      expect(restored.isSaved(item('one')), isTrue);
      await restored.setHidden(item('one'), false);
      expect(restored.isHidden(item('one')), isFalse);
      library.dispose();
      restored.dispose();
    },
  );

  test('a corrupt saved item does not erase the rest of the list', () async {
    SharedPreferences.setMockInitialValues({
      MediaLibrary.storageKey: jsonEncode({
        'saved': [
          item('one').toJson(),
          {'id': 123},
          item('two').toJson(),
        ],
        'hidden': [item('three').toJson()],
      }),
    });
    final library = MediaLibrary();
    await library.load();
    expect(library.saved.map((item) => item.id), ['two', 'one']);
    expect(library.isHidden(item('three')), isTrue);
    library.dispose();
  });

  test('failed writes roll back and subsequent writes can recover', () async {
    final library = MediaLibrary();
    await library.load();
    final store = _FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    await expectLater(library.toggleSaved(item('one')), throwsStateError);
    expect(library.isSaved(item('one')), isFalse);
    final afterFailure = MediaLibrary();
    await afterFailure.load();
    expect(afterFailure.saved, isEmpty);
    afterFailure.dispose();
    store.fail = false;
    await library.toggleSaved(item('two'));
    expect(library.saved.map((item) => item.id), ['two']);
    final restored = MediaLibrary();
    await restored.load();
    expect(restored.saved.map((item) => item.id), ['two']);
    restored.dispose();
    library.dispose();
  });
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail) return false;
    return super.setValue(valueType, key, value);
  }
}
