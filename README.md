# Majika

Majika is a local-first Flutter prototype for building taste profiles from the services a person already uses, then recommending new things to watch, read, play, or listen to. The long-term idea is to connect services such as AniList, Spotify, Steam, movie/TV libraries, and reading apps, normalize their signals, and let local AI plus recommendation systems explain what the user might enjoy next.

The current first working slice is intentionally narrow: AniList public username import, local profile generation, local-AI-assisted recommendations when a model is configured, deterministic fallback behavior when it is not, and a redesigned glass UI based on the sketch in this session.

## Current Scope

- **First service:** AniList.
- **Import path:** public AniList username. OAuth is planned so private lists can be imported later, but it is not wired yet.
- **Recommendation path:** fetch public anime/manga list entries, AniList favorites, visible media characters/studios, derive a local taste profile, fetch trending/popular AniList candidates, rank them locally, and show match reasons.
- **Top-pick path:** when local AI is available, it chooses the lead result from the ranked candidate set and the UI labels it as an AI recommendation. Without a model, the deterministic ranker still picks a top recommendation.
- **Search path:** after import, the user can steer recommendations with tags, anime/manga type chips, every AniList format chip, an adult-content opt-in, and a plain search request. This is not a chat UI; the request should be interpreted into recommendation filters, AniList search constraints, and ranking boosts.
- **Tag ownership:** tags picked by the user are pinned/self-selected. Tags inferred from the text request are AI-selected and shown differently in the UI. Starting a new text search should clear stale AI-selected tags while preserving user-pinned tags.
- **Storage:** local/session-first prototype with no backend. Firebase sync is a future option, so service and repository boundaries should stay clean.
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

Recommended direction:

- Settings currently offers local model downloads including FunctionGemma 270M, Qwen3 0.6B, Qwen 2.5 1.5B Instruct, and Phi-4 Mini Instruct. FunctionGemma is the smallest beginner option; larger models are available for better reasoning when the device can handle them.
- Start with a Gemma 4 E2B `.litertlm` model as the recommended default once a polished model import UX is added.
- Settings expose the intended knobs: provider target, model download choice, optional local-server endpoint, search-interpretation toggle, and context-item budget.
- Keep deterministic summaries as fallback when no model is configured.
- Use local AI to turn natural-language searches like `romance movie about time travel` into structured tags/formats such as `Romance`, `Time Manipulation`, and `MOVIE`. Do not rely on a large synonym table as the main product path; deterministic parsing is only the no-model safety net.
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

## Known Limitations

- AniList OAuth is not implemented yet.
- Data is not persisted across devices yet.
- Firebase is not configured yet.
- Local model execution is currently used for search interpretation and top-pick selection. Profile summaries and broader recommendation explanations still fall back if inference is unavailable or fails.
- Steam, Spotify, movies/TV, and other services are placeholders.
- Recommendation scoring is deterministic and intentionally simple while the product loop is being proven.

## Roadmap

1. Persist imported profiles and the last used AniList username locally.
2. Add AniList OAuth for private lists.
3. Add model status persistence, delete/re-download controls, and richer model health checks.
4. Add Firebase sync as an optional account layer.
5. Add a second service, likely Steam or Spotify.
6. Improve recommendations with embeddings, cross-service clustering, and better freshness signals.
