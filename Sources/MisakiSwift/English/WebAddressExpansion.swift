import Foundation

/// Rewrites web addresses — URLs, bare domains, email addresses, and Markdown
/// links — into natural spoken words, so "https://www.google.com" reads as
/// *"google dot com"* instead of shredding into out-of-vocabulary fragments
/// that the g2p fallback hallucinates into garble (with `://` and `.` becoming
/// stray pauses and `/` vanishing entirely).
///
/// Pure String → String with no G2P machinery — like
/// `MarkdownTableExpansion.describeTables(_:)`, the app calls it *before*
/// chunking, and the transcript then displays (and highlights) the spoken
/// words. Detection always runs; `Style` picks the rendering, so an app-level
/// "off" state can still replace each address with the word "link" rather
/// than feeding raw URLs to synthesis.
public enum WebAddressExpansion {

  /// How a detected address is rendered.
  public enum Style: Sendable, Equatable {
    /// "google dot com slash search" — schemes, leading "www.", queries,
    /// fragments, and ports dropped; pronounceable segments spoken as words,
    /// the rest spelled; long or unspeakable paths capped with "and more".
    case natural
    /// Every detected address becomes the word "link".
    case placeholder
  }

  /// Replace every detected web address in `text` with its spoken rendering,
  /// leaving all other content untouched. The rendering is set off from
  /// adjacent prose with commas (pause markers) exactly when a letter or
  /// digit directly neighbors it on the same line.
  public static func speakAddresses(in text: String, style: Style = .natural) -> String {
    expand(text, style: style, allowMarkdown: true)
  }

  // MARK: - Detection

  private enum Kind {
    case markdownLink(anchor: NSRange)
    case schemeURL
    case mailto
    case wwwHost
    case email
    case bareDomain

    /// Whether the regex for this kind can overrun into trailing sentence
    /// punctuation (greedy tails). Email is `\b`-bounded and markdown is
    /// paren-bounded, so neither needs the trim.
    var needsTrailingTrim: Bool {
      switch self {
      case .schemeURL, .mailto, .wwwHost, .bareDomain: return true
      case .markdownLink, .email: return false
      }
    }
  }

  private struct Detection {
    let range: NSRange
    let kind: Kind
  }

  /// TLDs spoken as ordinary dictionary words ("google dot com"). All of
  /// these exist in the gold dictionaries, so none can fall to the fallback
  /// network.
  static let wordTLDs: Set<String> = [
    "com", "org", "net", "gov", "mil", "info", "biz", "app", "dev", "me",
    "tech", "cloud", "page", "news", "blog", "shop", "store", "site", "online",
  ]

  /// TLDs spelled letter-by-letter ("example dot I.O") — initialisms and
  /// country codes nobody pronounces as words.
  static let spelledTLDs: Set<String> = [
    "io", "ai", "co", "uk", "us", "ca", "au", "nz", "de", "fr", "es", "it",
    "nl", "jp", "cn", "in", "br", "ru", "ch", "se", "no", "dk", "fi", "ie",
    "za", "edu", "ac", "int", "tv", "fm", "ly", "gg", "xyz",
  ]

  // The bare-domain allowlist deliberately omits TLDs that collide with file
  // extensions and short words ("Node.js", "README.md", "script.sh", and
  // missing-space typos like "to.be") — a false expansion there would garble
  // worse than the status quo. Addresses written with a scheme or "www."
  // always match regardless of TLD.

  /// Longest-first so "com" can't be shadowed by "co".
  private static let sortedTLDs: [String] = wordTLDs.union(spelledTLDs)
    .sorted { ($0.count, $1) > ($1.count, $0) }

  private static let tldAlternation: String = sortedTLDs.joined(separator: "|")

  /// Bare-domain TLDs additionally reject mixed case (all-lower or ALL-CAPS
  /// only): OCR text drops spaces after periods ("…visit the site.In fact…"),
  /// and a case-blind ".in"/".it"/".no" would turn that sentence glue into a
  /// spoken domain. All-caps stays allowed for shouty flyer text
  /// ("VISIT EXAMPLE.COM"). Scheme/www/mailto forms remain case-insensitive.
  private static let bareTldAlternation: String = sortedTLDs
    .flatMap { [$0, $0.uppercased()] }
    .joined(separator: "|")

  /// Characters that can never be part of an address: whitespace plus the
  /// quoting/angle characters prose wraps links in.
  private static let terminator = "[^\\s<>\"“”‘’]"

  private static let markdownRegex = try! NSRegularExpression(
    // Anchor, then a payload that must look like an address (scheme, www.,
    // mailto:, an email, or an allowlisted bare domain). Misaki's own
    // pronunciation-override links — [word](/fˈOnimz/), [word](2),
    // [word](#flag#) — fail every payload branch and pass through untouched
    // for EnglishG2P.preprocess to consume.
    pattern: "\\[([^\\]\\n]+)\\]\\(\\s*(?:(?:https?://|www\\.|mailto:)[^)\\s]+"
      + "|[A-Za-z0-9._%+-]+@[^)\\s]+"
      + "|[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.(?:\(tldAlternation))(?:[/?#][^)\\s]*)?)\\s*\\)",
    options: [.caseInsensitive])

  private static let schemeRegex = try! NSRegularExpression(
    pattern: "\\bhttps?://\(terminator)+", options: [.caseInsensitive])

  private static let mailtoRegex = try! NSRegularExpression(
    pattern: "\\bmailto:\(terminator)+", options: [.caseInsensitive])

  private static let wwwRegex = try! NSRegularExpression(
    pattern: "(?<![\\w.@-])www\\d{0,3}\\.\(terminator)+", options: [.caseInsensitive])

  private static let emailRegex = try! NSRegularExpression(
    // Generic TLD — the @ is the guard; the allowlist only gates bare domains.
    pattern: "(?<![\\w.@-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,24}\\b",
    options: [.caseInsensitive])

  private static let bareRegex = try! NSRegularExpression(
    // Case-sensitive (see bareTldAlternation). The (?!\.?[A-Za-z0-9])
    // lookahead rejects dotted glue ("google.com.Also") outright —
    // conservative: don't touch what we can't parse. The [/?#] tail keeps a
    // pathless query ("google.com?q=x") inside the match so it can't be left
    // behind as garble text.
    pattern: "(?<![\\w.@-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+"
      + "(?:\(bareTldAlternation))(?!\\.?[A-Za-z0-9])(?::\\d+)?(?:[/?#]\(terminator)*)?",
    options: [])

  /// All matches, priority-ordered (markdown > scheme > mailto > www > email >
  /// bare domain) with lower-priority matches dropped when they overlap an
  /// accepted one, then sorted by position.
  private static func detections(in text: String, allowMarkdown: Bool) -> [Detection] {
    let full = NSRange(location: 0, length: (text as NSString).length)
    var accepted: [Detection] = []

    func collect(_ regex: NSRegularExpression, _ kind: @escaping (NSTextCheckingResult) -> Kind) {
      regex.enumerateMatches(in: text, range: full) { match, _, _ in
        guard let match,
              !accepted.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 })
        else { return }
        accepted.append(Detection(range: match.range, kind: kind(match)))
      }
    }

    if allowMarkdown { collect(markdownRegex) { .markdownLink(anchor: $0.range(at: 1)) } }
    collect(schemeRegex) { _ in .schemeURL }
    collect(mailtoRegex) { _ in .mailto }
    collect(wwwRegex) { _ in .wwwHost }
    collect(emailRegex) { _ in .email }
    collect(bareRegex) { _ in .bareDomain }

    return accepted.sorted { $0.range.location < $1.range.location }
  }

  // MARK: - Rebuild

  private static func expand(_ text: String, style: Style, allowMarkdown: Bool) -> String {
    let found = detections(in: text, allowMarkdown: allowMarkdown)
    guard !found.isEmpty else { return text }

    let ns = text as NSString
    var out = ""
    var cursor = 0
    for detection in found {
      var range = detection.range
      if detection.kind.needsTrailingTrim {
        let overrun = trailingOverrunLength(of: ns.substring(with: range))
        range.length -= overrun
      }
      out += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
      let rendered = render(ns.substring(with: range), kind: detection.kind, style: style, in: ns)
      append(rendered, to: &out, nextCharacter: firstCharacterOnLine(in: ns, after: range))
      cursor = range.location + range.length
    }
    out += ns.substring(from: cursor)
    return out
  }

  /// UTF-16 length of trailing sentence punctuation the greedy tail regexes
  /// swallowed. Closing brackets only count when unbalanced, preserving
  /// addresses that legitimately end in one ("…/wiki/Foo_(bar)").
  private static func trailingOverrunLength(of candidate: String) -> Int {
    var kept = Substring(candidate)
    while let last = kept.last, ".,;:!?…\"'”’)]".contains(last) {
      if last == ")" || last == "]" {
        let open: Character = last == ")" ? "(" : "["
        guard kept.filter({ $0 == last }).count > kept.filter({ $0 == open }).count else { break }
      }
      kept = kept.dropLast()
    }
    return candidate.utf16.count - String(kept).utf16.count
  }

  /// Appends `rendered` with the boundary-comma rule: a comma attaches to the
  /// preceding word when a letter/digit precedes on the same line, and follows
  /// the rendering when a letter/digit comes next on the same line. Line
  /// breaks suppress both (a URL on its own line reads as its own clause).
  private static func append(_ rendered: String, to out: inout String, nextCharacter: Character?) {
    let gap = String(out.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
    let body = out.dropLast(gap.count)
    if let last = body.last, last.isLetter || last.isNumber {
      out = String(body) + "," + gap
    }
    out += rendered
    if let next = nextCharacter, next.isLetter || next.isNumber {
      out += ","
    }
  }

  /// The first non-space character after `range`, or nil at a line break or
  /// end of text.
  private static func firstCharacterOnLine(in ns: NSString, after range: NSRange) -> Character? {
    var location = range.location + range.length
    while location < ns.length {
      guard let scalar = UnicodeScalar(ns.character(at: location)) else { return nil }
      let character = Character(scalar)
      if character == " " || character == "\t" { location += 1; continue }
      return character == "\n" || character == "\r" ? nil : character
    }
    return nil
  }

  // MARK: - Rendering

  private static func render(_ raw: String, kind: Kind, style: Style, in ns: NSString) -> String {
    if case .markdownLink(let anchorRange) = kind {
      let anchor = ns.substring(with: anchorRange).trimmingCharacters(in: .whitespaces)
      let spoken = expand(anchor, style: style, allowMarkdown: false)
      // An anchor that is itself just an address collapses to one "link" in
      // placeholder style instead of the stutter "link, link".
      if style == .placeholder && spoken == "link" { return "link" }
      return spoken + ", link"
    }
    if style == .placeholder { return "link" }
    return naturalWords(for: parse(raw, kind: kind))
  }

  private struct ParsedAddress {
    var hostLabels: [String] = []
    var pathSegments: [String] = []
    var emailLocal: String?
    var droppedContent = false
  }

  private static func parse(_ raw: String, kind: Kind) -> ParsedAddress {
    var rest = Substring(raw)
    for prefix in ["https://", "http://", "mailto:"] where rest.count >= prefix.count {
      if rest.prefix(prefix.count).lowercased() == prefix {
        rest = rest.dropFirst(prefix.count)
        break
      }
    }

    var parsed = ParsedAddress()
    if let hash = rest.firstIndex(of: "#") {
      if rest.index(after: hash) < rest.endIndex { parsed.droppedContent = true }
      rest = rest[..<hash]
    }
    if let query = rest.firstIndex(of: "?") {
      if rest.index(after: query) < rest.endIndex { parsed.droppedContent = true }
      rest = rest[..<query]
    }

    var host = rest
    if let slash = rest.firstIndex(of: "/") {
      host = rest[..<slash]
      parsed.pathSegments = rest[rest.index(after: slash)...]
        .split(separator: "/")
        .map { String($0).removingPercentEncoding ?? String($0) }
    }

    // user@host: the local part is spoken for emails and dropped for URL
    // userinfo ("https://user@example.com/…").
    if let at = host.lastIndex(of: "@") {
      switch kind {
      case .email, .mailto: parsed.emailLocal = String(host[..<at])
      default: break
      }
      host = host[host.index(after: at)...]
    }
    if let colon = host.lastIndex(of: ":"),
       host[host.index(after: colon)...].allSatisfy(\.isNumber) {
      host = host[..<colon]
    }

    var labels = host.split(separator: ".").map(String.init)
    if labels.count > 1,
       labels[0].range(of: "^www\\d{0,3}$", options: [.regularExpression, .caseInsensitive]) != nil {
      labels.removeFirst()
    }
    parsed.hostLabels = labels
    return parsed
  }

  /// Path budget: at most this many segments, and at most this many spoken
  /// words across them, before capping with "and more". Hosts always read in
  /// full — they're the identity of the address.
  private static let maxPathSegments = 3
  private static let maxPathWords = 12

  private static func naturalWords(for parsed: ParsedAddress) -> String {
    var words: [String] = []

    if let local = parsed.emailLocal {
      let prepared = local
        .replacingOccurrences(of: "+", with: " plus ")
        .replacingOccurrences(of: "%", with: " percent ")
      words.append(spokenSegment(prepared))
      words.append("at")
    }

    let labelCount = parsed.hostLabels.count
    let host = parsed.hostLabels.enumerated().map { index, label in
      index == labelCount - 1 ? spokenFinalLabel(label) : spokenPart(label)
    }
    words.append(host.joined(separator: " dot "))

    var emitted = 0
    var pathWords = 0
    var truncated = false
    for segment in parsed.pathSegments {
      guard emitted < maxPathSegments, let spoken = speakableSegment(segment) else {
        truncated = true
        break
      }
      let count = spoken.split(separator: " ").count
      guard pathWords + count <= maxPathWords else {
        truncated = true
        break
      }
      words.append("slash")
      words.append(spoken)
      emitted += 1
      pathWords += count
    }

    var result = words.filter { !$0.isEmpty }.joined(separator: " ")
    if parsed.droppedContent || truncated { result += ", and more" }
    return result
  }

  /// The host's last label: a word for word TLDs, spelled for initialism
  /// TLDs, and the general word-or-spell heuristic for anything else
  /// (scheme-forced unknown TLDs, hosts with no real TLD).
  private static func spokenFinalLabel(_ label: String) -> String {
    let lowered = label.lowercased()
    if wordTLDs.contains(lowered) { return lowered }
    if spelledTLDs.contains(lowered) { return spelledLetters(Substring(label)) }
    return spokenPart(label)
  }

  /// A path segment (or email local): dot-parts spoken individually so
  /// "report.pdf" reads "report dot P.D.F". Returns nil when the segment is
  /// unspeakable — a hash/ID that would spell out at length (an alpha run of
  /// 5+ letters that isn't a word) or churn between letters and digits 4+
  /// times ("x7Kq9aZ3") — so the caller can cap with "and more" instead.
  private static func speakableSegment(_ segment: String) -> String? {
    var runs = 0
    for part in segment.split(separator: ".") {
      for run in alphanumericRuns(in: part) {
        runs += 1
        if runs >= 4 { return nil }
        if run.first!.isLetter && run.count >= 5 && !isWordish(run) { return nil }
      }
    }
    return spokenSegment(segment)
  }

  /// "report.pdf" → "report dot P.D.F"; parts between dots render via
  /// `spokenPart`.
  private static func spokenSegment(_ segment: String) -> String {
    segment.split(separator: ".").map { spokenPart(String($0)) }.joined(separator: " dot ")
  }

  /// Word-or-spell rendering of one dot-free part: separators and symbols
  /// become spaces, digit runs pass through for the number machinery, wordish
  /// letter runs lowercase ("Google" → "google"), and the rest spell as
  /// dotted capitals ("cnn" → "C.N.N" — dotted, not spaced, because a bare
  /// spaced "A" tags as a determiner and reads as schwa "uh", while dotted
  /// capitals ride the shipped M.R.C.S. acronym path).
  private static func spokenPart(_ part: String) -> String {
    let spaced = String(part.map { $0.isLetter || $0.isNumber ? $0 : " " })
    var pieces: [String] = []
    for piece in spaced.split(separator: " ") {
      for run in alphanumericRuns(in: piece) {
        if run.first!.isNumber {
          pieces.append(String(run))
        } else if isWordish(run) {
          pieces.append(run.lowercased())
        } else {
          pieces.append(spelledLetters(run))
        }
      }
    }
    return pieces.joined(separator: " ")
  }

  /// Maximal single-kind runs: "route66" → ["route", "66"].
  private static func alphanumericRuns(in piece: Substring) -> [Substring] {
    var runs: [Substring] = []
    var start = piece.startIndex
    var index = piece.startIndex
    while index < piece.endIndex {
      let next = piece.index(after: index)
      if next == piece.endIndex || piece[next].isNumber != piece[index].isNumber {
        runs.append(piece[start..<next])
        start = next
      }
      index = next
    }
    return runs
  }

  /// Two-letter words common in addresses ("my-site", "contact-us") that
  /// would otherwise spell. Deliberately curated instead of dictionary-driven:
  /// the gold dictionaries know one- and two-letter strings ("x", "co") whose
  /// address reading is still the spelled one.
  private static let shortWords: Set<String> = [
    "am", "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is",
    "it", "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we",
  ]

  /// Lowercased keys of both gold dictionaries — "does the pronunciation
  /// dictionary know this string". Loaded once on first use; a known string
  /// is guaranteed a correct reading downstream, an unknown one falls to the
  /// fallback network's guesswork.
  private static let goldWords: Set<String> = {
    var words: Set<String> = []
    for british in [false, true] {
      for key in DataResourcesUtil.loadGold(british: british).keys {
        words.insert(key.lowercased())
      }
    }
    return words
  }()

  /// Whether an alpha run reads as a word (vs spelling letter-by-letter).
  /// Three-letter runs are the genuinely ambiguous zone ("fox" vs "irs"), so
  /// they defer to the gold dictionaries: known → the engine says it right;
  /// unknown → initialism, spell it (I.R.S, N.Y.C, C.N.N, A.P.I). Longer runs
  /// lean word when they contain a vowel (concatenations like
  /// "binaryteaparty" aren't in any dictionary but the fallback network reads
  /// English-like strings acceptably); y is not counted a vowel so "hgtv"
  /// still spells.
  private static func isWordish(_ run: Substring) -> Bool {
    let lowered = run.lowercased()
    switch run.count {
    case ...2: return shortWords.contains(lowered)
    case 3: return goldWords.contains(lowered)
    default: return lowered.contains { "aeiou".contains($0) }
    }
  }

  /// "ca" → "C.A", "x" → "X" — uppercase, dot-joined, no trailing period.
  private static func spelledLetters(_ run: Substring) -> String {
    run.uppercased().map(String.init).joined(separator: ".")
  }
}
