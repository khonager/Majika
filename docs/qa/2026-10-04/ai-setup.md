# In-app AI setup — 2026-10-04

## What changed

Majika now offers a public model download directly in Settings → Local AI, including when the app is in rules-only mode. FLM, Ollama, cloud API keys and Hugging Face accounts are optional. Models requiring license access are behind Advanced model choice.

The default public choice is Qwen 2.5 1.5B Instruct (about 1.6 GB). Desktop users can also choose Qwen3 0.6B (about 586 MiB). Majika selects a suggestion using platform and detected RAM, and checks free storage on Android/iOS. It reports unknown capacity honestly. The guidance uses conservative RAM thresholds, not measured speed or recommendation-quality scores. Android uses the MediaPipe `.task` artifact for Qwen 2.5; desktop uses `.litertlm`. Artifact availability and platform formats were checked against the [model repository](https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct) and [installed runtime documentation](https://pub.dev/packages/flutter_gemma/versions/0.12.6).

A download belongs to the application, so leaving Settings does not abandon its progress or activation. After transfer, Majika loads the model on CPU and requires a text response before marking it ready. Download and check failures keep the previous AI settings; retry is available. Canceling cannot activate a late transfer. On restart, installed files are registered with the runtime again; interrupted installation intent is recovered. A missing file offers Download again.

On-device mode no longer silently uses a saved cloud key. **Use cloud AI if needed** is a separate, initially disabled option. Small local models remain subject to Majika's output validation and deterministic fallbacks; a successful load check does not establish recommendation accuracy.

The Gemini defaults and older saved IDs migrate to Gemini 3.5 Flash-Lite / Flash. Model-not-found errors now explain the recovery action without a raw JSON dump, and the tools path does not retry the same unavailable model as text-only. Google's [model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) confirms the replacement ID; its [OpenAI-compatible endpoint](https://ai.google.dev/gemini-api/docs/openai) remains supported.

## Try it as a user

1. Rebuild and launch the updated app (`flutter run -d linux`, or install the new debug APK on Android). Hot reload alone does not install new native plugins.
2. Open **Settings → Local AI**. Leave the server/cloud fields alone. Check the suggested model's size and device guidance, then press **Download**.
3. Leave Settings and browse recommendations. The application-wide notice should keep showing progress. On Android, allow notifications, put Majika in the background, and check the download notification and progress bar.
4. Wait for **Checking…**, then **ready to use**. Majika activates the model automatically. Its first load may take longer than later requests.
5. Import a public AniList list, then try a short request such as “a mystery anime series” or “a lighthearted comedy”. Check the inferred filters and results. A catalog connection is still needed to fetch new titles; model inference runs locally.
6. Close and reopen Majika. The model should remain available without another download. Open Settings to confirm its ready state.
7. Try canceling a different download, and try a connection interruption. Cancel must not switch the active model; a failed download should offer a retry.
8. To verify the reported Gemini fix separately, select **External cloud API → Google Gemini** and check that the selected model is **Gemini 3.5 Flash-Lite**. Existing keys are retained. Live account access and quota still depend on Google.

To test the earlier product changes, save a recommendation, restart, and open Saved; hide a title and restore it; refresh an imported library while offline and confirm the cached profile remains accessible.

## Background behavior and limits

| Platform | Expected behavior |
| --- | --- |
| Android | Native background transfer with notification progress/cancel, subject to OS restrictions and notification permission. |
| iOS | Native background transfer and state notifications; iOS does not show a continuously updating notification progress bar. In-app progress remains available. |
| Linux/macOS/Windows | Download continues while navigating or minimizing the running app, with an in-app notice. Quitting stops desktop execution; pending work is recovered on reopening. |

Hugging Face transfers may restart from zero after interruption; resumable byte ranges are not promised. Force-stop, loss of connectivity, disk exhaustion and OS power restrictions can interrupt native work. Mobile notification behavior follows the downloader's [platform contract](https://pub.dev/packages/background_downloader/versions/9.5.5).

CPU is used for the initial check and activated configuration. Advanced users can choose another backend later. No NPU/GPU performance claim is made. iOS/macOS/Windows runtime behavior and Android background notifications still require device verification.

## Developer checks

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter run -d linux -t tool/on_device_smoke.dart
```

The smoke entrypoint downloads a real public Qwen3 model, loads it through the bundled runtime, requires generated text, and exits with success/failure. It can use `--dart-define=MODEL_ID=qwen25_1_5b_instruct` for the larger model. Use separate application data directories when running it against a development machine with an existing Majika profile. It does not require FLM or Ollama.
