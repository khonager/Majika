import 'package:flutter/foundation.dart';

class AiConsoleLog extends ChangeNotifier implements ValueListenable<String> {
  final _buffer = StringBuffer();
  final _summaryBuffer = StringBuffer();

  @override
  String get value => _buffer.toString();

  String get summaryValue => _summaryBuffer.toString();

  bool get isEmpty => _buffer.isEmpty;

  void addUserLine(String message) {
    _write(message, includeInRaw: true, includeInSummary: true);
  }

  void addDetail(String message) {
    _write(message, includeInRaw: true, includeInSummary: false);
  }

  void addLine(String message) {
    addUserLine(message);
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

  void _write(
    String message, {
    required bool includeInRaw,
    required bool includeInSummary,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    final line = '[$timestamp] $trimmed';
    if (includeInRaw) {
      _buffer.writeln(line);
    }
    if (includeInSummary) {
      _summaryBuffer.writeln(line);
    }
    notifyListeners();
  }
}
