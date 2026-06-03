import 'package:flutter/foundation.dart';

class AiConsoleLog extends ChangeNotifier implements ValueListenable<String> {
  final _buffer = StringBuffer();

  @override
  String get value => _buffer.toString();

  bool get isEmpty => _buffer.isEmpty;

  void addLine(String message) {
    if (message.trim().isEmpty) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    _buffer.writeln('[$timestamp] $message');
    notifyListeners();
  }

  void addSection(String title, String content) {
    addLine(title);
    _buffer.writeln(content.trimRight());
    _buffer.writeln();
    notifyListeners();
  }
}
