import Foundation

/// Rescues Latin-script words carrying diacritics (Nariño, café, résumé) that
/// would otherwise slip past both pronunciation layers: the gold/silver
/// dictionaries are keyed by ASCII spellings only, and the fallback network's
/// grapheme alphabet is ASCII-only, so an accented letter used to reach it as
/// the UNKNOWN token and the model hallucinated syllables around the hole.
enum AccentedLatin {
  /// Loanwords whose accented spelling must not be resolved by plain
  /// diacritic folding: either the folded form collides with a different
  /// English word (résumé/resume, rosé/rose, exposé/expose, pâté/pate) or the
  /// dictionaries lack the word outright (jalapeño, piñata, señor). Keyed by
  /// the lowercased accented form, so unaccented spellings are never
  /// affected. Values follow each dialect's gold phoneme conventions,
  /// including ɾ for the American flapped t.
  static let loanwords: [String: (us: String, gb: String)] = [
    "cliché": (us: "kliʃˈA", gb: "klˈiːʃA"),
    "crème": (us: "kɹˈɛm", gb: "kɹˈɛm"),
    "crêpe": (us: "kɹˈAp", gb: "kɹˈɛp"),
    "déjà": (us: "dAʒˈɑ", gb: "dAʒˈɑː"),
    "doppelgänger": (us: "dˈɑpᵊlɡˌæŋəɹ", gb: "dˈɒpᵊlɡˌaŋə"),
    "entrée": (us: "ˈɑntɹˌA", gb: "ˈɒntɹA"),
    "exposé": (us: "ˌɛkspOzˈA", gb: "ɛkspˈQzA"),
    "fiancé": (us: "fˌiɑnsˈA", gb: "fiˈɒnsA"),
    "fiancée": (us: "fˌiɑnsˈA", gb: "fiˈɒnsA"),
    "jalapeño": (us: "hˌɑləpˈAnjO", gb: "hˌaləpˈAnjQ"),
    "mañana": (us: "mɑnjˈɑnə", gb: "manjˈɑːnə"),
    "mêlée": (us: "mˈAlˌA", gb: "mˈɛlA"),
    "née": (us: "nˈA", gb: "nˈA"),
    "niña": (us: "nˈinjə", gb: "nˈiːnjə"),
    "niño": (us: "nˈinjO", gb: "nˈiːnjQ"),
    "pâté": (us: "pɑtˈA", gb: "pˈatA"),
    "piñata": (us: "pɪnjˈɑɾə", gb: "pɪnjˈɑːtə"),
    "protégé": (us: "pɹˈOɾəʒˌA", gb: "pɹˈɒtɪʒA"),
    "protégée": (us: "pɹˈOɾəʒˌA", gb: "pɹˈɒtɪʒA"),
    "résumé": (us: "ɹˈɛzəmˌA", gb: "ɹˈɛzjʊmˌA"),
    "rosé": (us: "ɹOzˈA", gb: "ɹˈQzA"),
    "sauté": (us: "sOtˈA", gb: "sˈQtA"),
    "señor": (us: "sAnjˈɔɹ", gb: "sɛnjˈɔː"),
    "señora": (us: "sAnjˈɔɹə", gb: "sɛnjˈɔːɹə"),
    "soirée": (us: "swɑɹˈA", gb: "swˈɑːɹA"),
    "touché": (us: "tuʃˈA", gb: "tuːʃˈA"),
    "über": (us: "ˈubəɹ", gb: "ˈuːbə"),
  ]

  /// Letters `.diacriticInsensitive` folding leaves untouched because they
  /// have no Unicode decomposition, mapped to their conventional English
  /// respellings (Straße→Strasse, Łódź→Lodz).
  private static let unfoldableLetters: [Character: String] = [
    "ß": "ss", "æ": "ae", "Æ": "Ae", "œ": "oe", "Œ": "Oe",
    "ø": "o", "Ø": "O", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D",
    "ð": "d", "Ð": "D", "þ": "th", "Þ": "Th",
  ]

  /// Rewrites applied only on the way into the fallback network, where the
  /// goal is a pronounceable respelling rather than the conventional English
  /// spelling: ñ keeps its palatal glide (Nariño→Narinyo) and ç keeps its
  /// soft sound (Besançon→Besanson) instead of folding to n and hard c.
  private static let fallbackLetters: [Character: String] =
    unfoldableLetters.merging(["ñ": "ny", "Ñ": "Ny", "ç": "s", "Ç": "S"]) { current, _ in current }

  /// Folds a word to the conventional English/ASCII respelling used for
  /// dictionary lookups: café→cafe, façade→facade, Zürich→Zurich.
  static func foldedSpelling(_ word: String) -> String {
    transliterate(word, with: unfoldableLetters)
  }

  /// Respells a word for the fallback network's ASCII-only grapheme
  /// alphabet, favoring pronunciation over spelling: Nariño→Narinyo,
  /// Curaçao→Curasao. ASCII input comes back unchanged; non-Latin scripts
  /// (Cyrillic, Greek, CJK) pass through and still become unknown tokens —
  /// only Latin diacritics are in scope here.
  static func fallbackRespelling(_ word: String) -> String {
    transliterate(word, with: fallbackLetters)
  }

  private static func transliterate(_ word: String, with map: [Character: String]) -> String {
    guard !word.allSatisfy(\.isASCII) else { return word }

    var respelled = ""
    for character in word {
      if let replacement = map[character] {
        respelled += replacement
      } else {
        respelled.append(character)
      }
    }
    return respelled.folding(options: .diacriticInsensitive, locale: nil)
  }
}
