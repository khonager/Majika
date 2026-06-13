import 'package:flutter/foundation.dart';

class AiConsoleLog extends ChangeNotifier implements ValueListenable<String> {
  final _buffer = StringBuffer();
  final _summaryBuffer = StringBuffer();

  @override
  String get value => _buffer.toString();

  String get summaryValue => _summaryBuffer.toString();

  bool get isEmpty => _buffer.isEmpty;

  void addLine(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    _buffer.writeln('[$timestamp] $trimmed');
    _summaryBuffer.writeln('[$timestamp] $trimmed');
    notifyListeners();
  }

  void addSection(String title, String content) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty || content.trim().isEmpty) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    _buffer.writeln('[$timestamp] $trimmedTitle');
    _buffer.writeln(content.trimRight());
    _buffer.writeln();
    notifyListeners();
  }
}
