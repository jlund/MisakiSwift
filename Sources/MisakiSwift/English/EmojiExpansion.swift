import Foundation

/// Expands emoji into their spoken English names so the TTS engine reads
/// "☀️ Summer" as *"sun emoji … Summer"* instead of garbling the glyph.
///
/// Names come from a bundled table derived from Unicode's CLDR `type="tts"`
/// annotations (the same short names VoiceOver speaks), restricted to the RGI
/// emoji set and pre-normalized to plain space-separated words. See
/// `Scripts/generate_emoji_names.py` and `Resources/emoji_names.json`.
///
/// The detection/normalization here is the single source of truth for "what is
/// an emoji" — both the g2p expansion (`expansions(in:)`, used by
/// `EnglishG2P`) and the app's opt-out path (`stripEmoji(_:)`) go through it.
public enum EmojiExpansion {

  /// Variation selector-16: forces emoji presentation. Stripped from both the
  /// table keys (at generation time) and input clusters (here) so `❤` and `❤️`
  /// resolve to the same entry.
  private static let variationSelector16: Unicode.Scalar = "\u{FE0F}"

  /// Bundled `{ FE0F-stripped emoji : space-separated spoken name }` table,
  /// loaded once. Mirrors `DataResourcesUtil`'s `Bundle.module` resource path.
  static let names: [String: String] = {
    guard
      let url = Bundle.module.url(
        forResource: "emoji_names", withExtension: "json", subdirectory: "Resources"),
      let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else {
      return [:]
    }
    return json
  }()

  /// The canonical lookup key for a grapheme cluster: the cluster with every
  /// U+FE0F removed.
  static func canonicalKey(for cluster: String) -> String {
    String(cluster.unicodeScalars.filter { $0 != variationSelector16 })
  }

  /// The spoken name for a single emoji grapheme cluster, or `nil` if the
  /// cluster is not a known emoji. Table membership *is* the emoji test — this
  /// naturally excludes bare digits / `#` / `*` (only the full keycap
  /// sequences like `3️⃣` are keys).
  static func name(for cluster: String) -> String? {
    names[canonicalKey(for: cluster)]
  }

  /// One maximal run of emoji — consecutive emoji clusters, optionally
  /// separated by inline whitespace — already expanded for the
  /// surface-substitution machinery.
  struct EmojiRun {
    /// Span of the whole run in the source text, including any inline
    /// whitespace between the run's emoji. The first restored token displays
    /// `originalText`, keeping the chyron verbatim.
    let originalRange: Range<String.Index>
    /// The run's glyphs exactly as typed (e.g. `"❤️❤️❤️"`, `"❤️ ❤️"`).
    let originalText: String
    /// One entry per word NLTagger will produce from the expansion, in order.
    /// Repeated emoji collapse to a leading count digit (`"3"` → *"three"* via
    /// the existing number path); distinct groups read as a natural list with
    /// "and" before the final group and a single trailing "emoji"
    /// (`"☀️🎉"` → *"sun, and party popper emoji"*).
    let lookupWords: [String]
    /// Indices into `lookupWords` after which `tokenize()` injects a
    /// comma-strength pause token: the boundary after each non-final group's
    /// last word (i.e. just before the next name, or before the "and").
    let pauseAfterWordIndices: [Int]
  }

  /// Find every maximal emoji run in `text`, in order. Emoji separated only by
  /// inline whitespace (spaces, tabs, NBSP — anything whitespace that isn't a
  /// newline) join the same run, so `"❤️ ❤️ ❤️"` groups exactly like
  /// `"❤️❤️❤️"`. Newlines break a run.
  static func expansions(in text: String) -> [EmojiRun] {
    struct Group { let key: String; let name: String; var count: Int }
    var runs: [EmojiRun] = []
    var index = text.startIndex

    while index < text.endIndex {
      let clusterEnd = text.index(after: index)
      let cluster = String(text[index..<clusterEnd])
      guard let firstName = name(for: cluster) else {
        index = clusterEnd
        continue
      }

      // Accumulate (key, name, count) groups so identical emoji — adjacent or
      // gap-separated — collapse into a single counted phrase. Each extension
      // step consumes the next emoji cluster, optionally preceded by a gap of
      // inline whitespace; the gap is only committed into the run if an emoji
      // actually follows it, so trailing whitespace is never absorbed.
      var groups = [Group(key: canonicalKey(for: cluster), name: firstName, count: 1)]
      let runStart = index
      var runEnd = clusterEnd
      while runEnd < text.endIndex {
        var probe = runEnd
        while probe < text.endIndex, text[probe].isWhitespace, !text[probe].isNewline {
          probe = text.index(after: probe)
        }
        guard probe < text.endIndex else { break }
        let nextEnd = text.index(after: probe)
        let nextCluster = String(text[probe..<nextEnd])
        guard let spoken = name(for: nextCluster) else { break }
        let key = canonicalKey(for: nextCluster)
        if groups[groups.count - 1].key == key {
          groups[groups.count - 1].count += 1
        } else {
          groups.append(Group(key: key, name: spoken, count: 1))
        }
        runEnd = nextEnd
      }

      // Natural-list phrasing: "g1, g2, and g3 emoji" — a single trailing
      // "emoji", "and" before the final group, and a comma-strength pause
      // (recorded as metadata; tokenize() injects the actual tokens) after
      // each non-final group. The pause stays before "and" even for two-group
      // runs: many CLDR names contain a literal "and" ("skull and
      // crossbones"), and the pause is what keeps the list audible.
      var lookupWords: [String] = []
      var pauseAfterWordIndices: [Int] = []
      for (i, group) in groups.enumerated() {
        if i > 0 {
          pauseAfterWordIndices.append(lookupWords.count - 1)
          if i == groups.count - 1 { lookupWords.append("and") }
        }
        if group.count >= 2 { lookupWords.append("\(group.count)") }
        lookupWords.append(contentsOf: group.name.split(separator: " ").map(String.init))
      }
      lookupWords.append("emoji")

      runs.append(
        EmojiRun(
          originalRange: runStart..<runEnd,
          originalText: String(text[runStart..<runEnd]),
          lookupWords: lookupWords,
          pauseAfterWordIndices: pauseAfterWordIndices))
      index = runEnd
    }

    return runs
  }

  /// Remove every emoji from `text`, collapsing the whitespace the removals
  /// leave behind. Used by the app when "Pronounce Emoji Characters" is off so
  /// emoji are silent (and absent from the synced transcript) rather than fed
  /// to the g2p fallback as garbage.
  public static func stripEmoji(_ text: String) -> String {
    var kept = ""
    var index = text.startIndex
    while index < text.endIndex {
      let clusterEnd = text.index(after: index)
      let cluster = String(text[index..<clusterEnd])
      if name(for: cluster) == nil { kept.append(cluster) }
      index = clusterEnd
    }
    // Collapse the runs of spaces/tabs a removed emoji can leave behind
    // ("a ☀️ b" → "a  b" → "a b") and trim the edges.
    let collapsed = kept.replacingOccurrences(
      of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
