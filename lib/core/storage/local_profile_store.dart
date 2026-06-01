import 'dart:convert';

import 'package:majika/core/models/media_item.dart';
import 'package:majika/core/models/recommendation_query.dart';
import 'package:majika/core/models/taste_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileSession {
  final String serviceId;
  final TasteProfile profile;
  final List<MediaItem> candidates;
  final List<String> serviceTags;
  final RecommendationQuery query;
  final bool adultCandidatesLoaded;
  final String userNameDraft;

  const LocalProfileSession({
    required this.serviceId,
    required this.profile,
    required this.candidates,
    required this.serviceTags,
    required this.query,
    required this.adultCandidatesLoaded,
    required this.userNameDraft,
  });

  factory LocalProfileSession.fromJson(Map<String, dynamic> json) {
    return LocalProfileSession(
      serviceId: json['serviceId'] as String? ?? '',
      profile: TasteProfile.fromJson(
        Map<String, dynamic>.from(json['profile'] as Map? ?? const {}),
      ),
      candidates: _mediaItemsFromJson(json['candidates']),
      serviceTags: _stringList(json['serviceTags']),
      query: RecommendationQuery.fromJson(
        Map<String, dynamic>.from(json['query'] as Map? ?? const {}),
      ),
      adultCandidatesLoaded: json['adultCandidatesLoaded'] as bool? ?? false,
      userNameDraft: json['userNameDraft'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serviceId': serviceId,
      'profile': profile.toJson(),
      'candidates': candidates.map((item) => item.toJson()).toList(),
      'serviceTags': serviceTags,
      'query': query.toJson(),
      'adultCandidatesLoaded': adultCandidatesLoaded,
      'userNameDraft': userNameDraft,
    };
  }

  LocalProfileSession copyWith({
    TasteProfile? profile,
    List<MediaItem>? candidates,
    List<String>? serviceTags,
    RecommendationQuery? query,
    bool? adultCandidatesLoaded,
    String? userNameDraft,
  }) {
    return LocalProfileSession(
      serviceId: serviceId,
      profile: profile ?? this.profile,
      candidates: candidates ?? this.candidates,
      serviceTags: serviceTags ?? this.serviceTags,
      query: query ?? this.query,
      adultCandidatesLoaded:
          adultCandidatesLoaded ?? this.adultCandidatesLoaded,
      userNameDraft: userNameDraft ?? this.userNameDraft,
    );
  }

  static List<MediaItem> _mediaItemsFromJson(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) MediaItem.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }
}

class LocalProfileStore {
  static const sessionsKey = 'profiles.sessions.v1';

  const LocalProfileStore();

  Future<Map<String, LocalProfileSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(sessionsKey);
    if (raw == null || raw.trim().isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): LocalProfileSession.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSession(LocalProfileSession session) async {
    final sessions = await loadSessions();
    sessions[session.serviceId] = session;
    await _saveSessions(sessions);
  }

  Future<void> removeSession(String serviceId) async {
    final sessions = await loadSessions();
    sessions.remove(serviceId);
    await _saveSessions(sessions);
  }

  Future<void> _saveSessions(Map<String, LocalProfileSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      sessionsKey,
      jsonEncode({
        for (final entry in sessions.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
