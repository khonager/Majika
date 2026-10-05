import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:majika/core/ai/cloud_ai_probe.dart';
import 'package:majika/core/ai/local_ai_settings.dart';

class CloudAiTestCard extends StatefulWidget {
  final String provider;
  final TextEditingController endpoint;
  final TextEditingController model;
  final TextEditingController apiKey;
  final http.Client Function()? clientFactory;

  const CloudAiTestCard({
    super.key,
    required this.provider,
    required this.endpoint,
    required this.model,
    required this.apiKey,
    this.clientFactory,
  });

  @override
  State<CloudAiTestCard> createState() => _CloudAiTestCardState();
}

class _CloudAiTestCardState extends State<CloudAiTestCard> {
  CloudAiProbeResult? _result;
  http.Client? _client;
  int _revision = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [widget.endpoint, widget.model, widget.apiKey]) {
      controller.addListener(_invalidate);
    }
  }

  @override
  void didUpdateWidget(CloudAiTestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final controller in [
      oldWidget.endpoint,
      oldWidget.model,
      oldWidget.apiKey,
    ]) {
      controller.removeListener(_invalidate);
    }
    for (final controller in [widget.endpoint, widget.model, widget.apiKey]) {
      controller.addListener(_invalidate);
    }
    if (oldWidget.provider != widget.provider ||
        oldWidget.endpoint != widget.endpoint ||
        oldWidget.model != widget.model ||
        oldWidget.apiKey != widget.apiKey) {
      _invalidate();
    }
  }

  void _invalidate() {
    _revision++;
    _client?.close();
    _client = null;
    setState(() {
      _result = null;
      _running = false;
    });
  }

  @override
  void dispose() {
    _revision++;
    _client?.close();
    for (final controller in [widget.endpoint, widget.model, widget.apiKey]) {
      controller.removeListener(_invalidate);
    }
    super.dispose();
  }

  Future<void> _test() async {
    final revision = ++_revision;
    final client = widget.clientFactory?.call() ?? http.Client();
    _client = client;
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await CloudAiProbe(client).run(
      LocalAiRuntimeSettings(
        useLocalAi: true,
        useAiForSearch: true,
        mode: localAiModeExternalCloud,
        provider: externalCloudAiProvider,
        endpoint: defaultLocalAiEndpoint,
        serverModel: defaultLocalAiModel,
        cloudProvider: widget.provider,
        cloudEndpoint: widget.endpoint.text,
        cloudModel: widget.model.text,
        cloudApiKey: widget.apiKey.text,
        contextItems: 24,
      ),
    );
    client.close();
    if (!mounted || revision != _revision) return;
    _client = null;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        widget.apiKey.text.trim().isNotEmpty &&
        widget.model.text.trim().isNotEmpty &&
        widget.endpoint.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3. Test required capabilities',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Checks structured responses and search-tool compatibility using sample data. Up to 3 requests, each capped at 256 output tokens. Uses provider quota and may cost money on paid accounts.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: ready && !_running ? _test : null,
            icon: Icon(
              _running ? Icons.hourglass_top : Icons.fact_check_outlined,
            ),
            label: Text(
              _running ? 'Testing capabilities…' : 'Test AI capabilities',
            ),
          ),
          if (!ready)
            const Text('Paste your key and choose a model to enable the test.'),
          if (_result case final result?)
            Semantics(
              liveRegion: true,
              child: Text(
                '${result.passed ? "Ready" : "Not verified"}: ${result.message}',
              ),
            ),
        ],
      ),
    );
  }
}
