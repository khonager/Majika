# Majika

Majika is a local-first Flutter prototype for building taste profiles from the services a person already uses, then recommending new things to watch, read, play, or listen to. The long-term idea is to connect services such as AniList, Spotify, Steam, movie/TV libraries, and reading apps, normalize their signals, and let local AI plus recommendation systems explain what the user might enjoy next.

Majika currently supports AniList public username imports and Steam public libraries, with recommendations, optional AI search, and a device-local saved list. Steam imports require a signed-in Majika account and the Firebase Steam backend; AniList and rules-only recommendations do not require AI setup.

## Everyday use

1. Connect AniList with a public username, or connect a public Steam profile after signing in from Profile.
2. Browse recommendations or search for a mood, tag, or format. On phones, expand **Filters** for more controls.
3. Use **Why this pick?** for the full explanation and description, and **Save for later** to keep a title.
4. Open **Saved** from the navigation rail or dock. Saved titles and hidden picks survive restarting the app and remain available offline; external catalog pages still require a connection.
5. Hide unwanted recommendations, undo the action, or restore them from **Hidden picks**.
6. Use **Refresh library** to import recent activity and update candidates. A failed refresh keeps the last imported profile. Resetting a service search uses its cached candidates without requiring the network.

See the [usability review and verification report](docs/qa/2026-10-03/review.md) for screenshots, coverage, and remaining limitations.

## Current Scope

- **First service:** AniList.
- **Import path:** public AniList username. OAuth is planned so private lists can be imported later, but it is not wired yet.
- **Recommendation path:** fetch public anime/manga list entries, AniList favorites, visible media characters/studios, derive a local taste profile, fetch trending/popular AniList candidates, rank them locally, and show match reasons.
- **Top-pick path:** when local AI is available, it chooses the lead result from the ranked candidate set and the UI labels it as an AI recommendation. Without a model, the deterministic ranker still picks a top recommendation.
- **Search path:** after import, the user can steer recommendations with tags, anime/manga type chips, every AniList format chip, an adult-content opt-in, and a plain search request. This is not a chat UI; the request should be interpreted into recommendation filters, AniList search constraints, and ranking boosts.
- **Tag ownership:** tags picked by the user are pinned/self-selected. Tags inferred from the text request are AI-selected and shown differently in the UI. Starting a new text search should clear stale AI-selected tags while preserving user-pinned tags.
- **Storage:** imported profiles, candidate caches, saved picks, and hidden picks persist locally. Firebase supports optional accounts and the protected Steam connector; saved picks are not synchronized between devices.
- **AI:** no remote AI API by default. The app can download or use a local model with `flutter_gemma`, tries the active local model for search interpretation and top-pick selection, and falls back to deterministic local rules when no model is configured or inference fails.
- **Extensions:** the Lua extension runner and `extensions/anilist_template.lua` are experimental extension work. The main app uses the typed Dart AniList connector for reliability.

## Product Direction

Majika should feel like a personal taste console, not a generic content feed. It should help answer:

- What does this user consistently like?
- What are they currently watching, reading, playing, or listening to?
- Which new releases or popular items are worth trying?
- Why is a recommendation a good match?

The app should eventually combine multiple service profiles into one cross-media taste model. For example, a user who likes psychological anime, atmospheric games, and moody electronic music should get recommendations that understand the overlap instead of treating each service as a silo.

## UI Direction

The black-ink top-left sketch is the main reference.

- Rounded app/content surface.
- Glassy service/menu rail.
- Mobile and tablet: rail on the left.
- Desktop: rail/dock at the bottom with vertical content scrolling.
- Settings button sits above or near the profile control in the rail/dock.
- Main content after import:
  - large top recommendation card, labeled as an AI recommendation when the local model chose it,
  - recommendation search/filter controls,
  - list of additional recommendations/currently popular items,
  - bottom “current/latest activity” bar.
- Palette: graphite glass, neutral dark background, milky translucent rail, restrained service accents.

## Architecture Notes

Important concepts live under `lib/core`:

- `MediaItem`: normalized media object across AniList now and future services later.
- `TasteProfile`: derived user profile with favorite genres, formats, high-rated items, and recent activity.
- `UserTasteSignals`: public AniList favorites such as favorite characters, staff, and studios.
- `Recommendation`: ranked candidate with score, signals, explanation, and whether it was chosen by AI.
- `MediaService`: interface for AniList, Steam, Spotify, movies/TV, etc.
- `AniListService`: typed GraphQL client for the first real service.
- `TasteEngine`: deterministic local profile and recommendation engine.
- `RecommendationQuery`: user-pinned filters, AI-selected filters, and inferred search hints kept separate so new searches can rethink AI tags without losing user choices.
- `LocalAiService`: abstraction for local model execution and deterministic fallback behavior.

The current home screen wires these pieces together directly for the prototype. As Majika grows, move persistence and orchestration behind repositories so Firebase sync can be added without replacing the UI or service connectors.

## Local AI Plan

Majika should use local AI by default, not a hosted API. The Flutter integration is [`flutter_gemma`](https://pub.dev/packages/flutter_gemma), with user-downloaded models instead of bundling a model in the app. The current app can download one of several supported local models, registers the chosen model as active, and uses it for natural-language search interpretation and AI top-pick selection when available. Deterministic local hints remain as the fallback when no model is installed or inference fails.

The desired search flow is:

1. User types a request such as `romance movie about time travel` or `obsessed character thriller`.
2. Local AI reads the request and chooses AniList-ready structured intent: media type, formats, AI-selected tags, adult-content intent, and search text.
3. The app fetches candidates from AniList using those structured constraints and ranks them against the user's taste profile.
4. Local AI can then choose the lead recommendation from the ranked candidate set and rewrite the reason for that pick.
5. If no local model is configured, Majika falls back to small deterministic hints and the local ranker so the prototype still returns useful results. These hints are not meant to replace the AI interpreter.

- Settings offers a single AI mode choice: Automatic on-device, External local server, or Rules only. On-device mode exposes platform-supported public no-token text model downloads; external mode exposes OpenAI-compatible endpoint fields and Gemma/Ollama model presets.
- The default on-device model should be chosen only after the benchmark harness validates initialization, JSON reliability, latency, and prompt quality for the current candidate set. Current public on-device candidates include Qwen3 0.6B, FunctionGemma 270M, DeepSeek R1 Distill Qwen 1.5B, Qwen 2.5 1.5B Instruct, SmolLM 135M, and Phi-4 Mini where supported by the current platform.
- FunctionGemma is a tiny function-calling foundation model, not a general JSON chat model. Keep it advanced unless Majika adds real tool declarations or task-specific fine-tuning for recommendation filters.
- Do not add Hugging Face token UX for standard users. Advanced users can import a model file they downloaded themselves once custom import is wired.
- Vision models such as FastVLM are intentionally excluded until Majika has an image-understanding workflow.
- Keep deterministic summaries as fallback when no model is configured.
- Use local AI to turn natural-language searches like `romance movie about time travel` into structured tags/formats such as `Romance`, `Time Manipulation`, and `MOVIE`. Do not rely on a large synonym table as the main product path; deterministic parsing is only the no-model safety net.
- Do not add hard-coded media knowledge such as title acronym maps, franchise aliases, creator shorthand, or one-off "if the user says X, search for Y" rules. Fix failed searches by improving grounding, service/API retrieval, prompt contracts, logging, or benchmark coverage.
- Let the app fetch current releases and service data itself, then pass structured context to the local model for summaries and recommendation explanations.
- Later, optional custom providers can be added for users who want their own API key or external local server.

Useful references:

- [`flutter_gemma` on pub.dev](https://pub.dev/packages/flutter_gemma)
- [AniList API docs](https://anilist.gitbook.io/anilist-apiv2-docs)
- [AniList API route/OAuth notes](https://anilist.gitbook.io/anilist-apiv2-docs/docs/guide/migration/version-1/index)

## Setup

This repo is a Flutter app.

```bash
flutter pub get
flutter run -d linux
```

The project also includes a Nix flake for a Flutter/Android-oriented development shell:

```bash
nix develop
```

Useful checks:

```bash
flutter analyze
flutter test
flutter build linux --debug
flutter build apk --debug
```

Public catalog smoke tests are opt-in because they require network access and
live AniList/Steam availability:

```bash
flutter test test/live_catalog_test.dart --dart-define=RUN_LIVE_CATALOG=true
```

These checks fetch public recommendations without creating an account or writing
to either service. The default test suite uses deterministic fixtures.

## Android Releases

Majika publishes rolling Android builds from two GitHub release channels:

[![Get stable in Obtainium](https://img.shields.io/badge/Obtainium-Stable-1f6feb?style=for-the-badge)](https://github.com/khonager/Majika/releases/tag/stable-latest)
[![Get unstable in Obtainium](https://img.shields.io/badge/Obtainium-Unstable-f97316?style=for-the-badge)](https://github.com/khonager/Majika/releases/tag/unstable-latest)

- Stable: `https://github.com/khonager/Majika/releases/tag/stable-latest`
- Unstable: `https://github.com/khonager/Majika/releases/tag/unstable-latest`

Paste either release URL into Obtainium's Add App screen. Majika's GitHub Android releases are intended to be signed with one persistent release key so updates install over the previous version instead of forcing an uninstall.

To make the GitHub Android workflows succeed, configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

If you do not already have a release keystore, generate one locally:

```bash
keytool -genkeypair \
  -v \
  -keystore android/upload-keystore.jks \
  -alias majika \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Then base64-encode it for GitHub Actions:

```bash
base64 -w 0 android/upload-keystore.jks
```

Use the generated one-line output as `ANDROID_KEYSTORE_BASE64`, and use the same alias/password values you entered for the other three secrets. Keep this keystore safe and reuse the same one for every future Android release, or Android will treat updates as incompatible.

Local AI model benchmark on Linux desktop:

```bash
flutter build linux --debug
flutter pub run scripts/local_ai_benchmark.dart
```

## Known Limitations

- AniList OAuth is not implemented yet.
- Saved picks and imported library caches are not synchronized across devices.
- Steam requires a configured Firebase backend and public game details. See [Firebase setup](docs/firebase_setup.md).
- Local model execution is currently used for search interpretation and top-pick selection. Profile summaries and broader recommendation explanations still fall back if inference is unavailable or fails.
- Spotify and movies/TV are not implemented; unfinished service buttons are not shown in navigation.
- Recommendation scoring is deterministic and intentionally simple while the product loop is being proven.

## Roadmap

1. Add AniList OAuth for private lists.
2. Improve model health checks and benchmark recommendation quality on real devices.
3. Add optional synchronization for saved picks and recommendation feedback.
4. Add freshness-aware discovery and richer signals from saved and hidden picks.
5. Validate authenticated service flows and accessibility on Android and iOS devices.
