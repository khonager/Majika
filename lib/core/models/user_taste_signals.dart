class UserTasteSignals {
  final List<String> favoriteCharacters;
  final List<String> favoriteStaff;
  final List<String> favoriteStudios;

  const UserTasteSignals({
    this.favoriteCharacters = const [],
    this.favoriteStaff = const [],
    this.favoriteStudios = const [],
  });

  static const empty = UserTasteSignals();
}
