import Foundation
import NaturalLanguage
import MLXUtilsLibrary

// Main G2P pipeline for English text
final public class EnglishG2P {
  private let british: Bool
  private let tagger: NLTagger
  private let lexicon: Lexicon
  private let fallback: EnglishFallbackNetwork
  private let unk: String
    
  static let punctuationTags: Set<NLTag> =  Set([.openQuote, .closeQuote, .openParenthesis, .closeParenthesis, .punctuation, .sentenceTerminator, .otherPunctuation])
  static let punctuactions: Set<Character> = Set(";:,.!?—…\"“”")
  
  // spaCy-style punctuation tags https://github.com/explosion/spaCy/blob/master/spacy/glossary.py
  static let punctuationTagPhonemes: [String: String] = [
      "``": String(UnicodeScalar(8220)!),     // Left double quotation mark
      "\"\"": String(UnicodeScalar(8221)!),   // Right double quotation mark
      "''": String(UnicodeScalar(8221)!)      // Right double quotation mark
  ]
  
  static let nonQuotePunctuations: Set<Character> = Set(punctuactions.filter { !"\"\"\"".contains($0) })
  static let vowels: Set<Character> = Set("AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ")
  static let consonants: Set<Character> = Set("bdfhjklmnpstvwzðŋɡɹɾʃʒʤʧθ")
  static let subTokenJunks: Set<Character> = Set("',-._''/")
  static let stresses = "ˌˈ"
  static let primaryStress = stresses[stresses.index(stresses.startIndex, offsetBy: 1)]
  static let secondaryStress = stresses[stresses.index(stresses.startIndex, offsetBy: 0)]
  // Splits words into subtokens such as acronym boundaries, signs, commas, decimals, multiple quotes, camelCase boundaries and so forth.
  static let subtokenizeRegexPattern = #"^[''']+|\p{Lu}(?=\p{Lu}\p{Ll})|(?:^-)?(?:\d?[,.]?\d)+|[-_]+|[''']{2,}|\p{L}*?(?:[''']\p{L})*?\p{Ll}(?=\p{Lu})|\p{L}+(?:[''']\p{L})*|[^-_\p{L}'''\d]|[''']+$"#
  static let subtokenizeRegex = try! NSRegularExpression(pattern: EnglishG2P.subtokenizeRegexPattern, options: [])

  // Regexes used to expand temperature measurements like "110°F" into spoken
  // form ("110 degrees Fahrenheit") before tokenization. The degree sign is
  // tagged as .otherWord by NLTagger and otherwise leaks into the fallback
  // network, producing garbled audio.
  //
  // Singular variants match exactly "1°" (not "11°", "21°", "0.1°", etc.) so
  // that "1°F" becomes "1 degree Fahrenheit" rather than "1 degrees Fahrenheit".
  //
  // The plural-form patterns capture the *full* number (including any leading
  // digits or a decimal part like "98.6") so the substitution-tracking layer
  // can record the entire user-facing surface form ("98.6°F"). The
  // surface-preservation pass after tokenize() needs the whole "98.6°F"
  // string to write back into token.text — capturing only the trailing digit
  // (`(\d)`) would let the chyron leak the modified "98.6 degrees Fahrenheit".
  private static let temperatureSingularFahrenheitRegex = try! NSRegularExpression(pattern: #"(?<![\d.])1°[Ff]\b"#, options: [])
  private static let temperatureSingularCelsiusRegex = try! NSRegularExpression(pattern: #"(?<![\d.])1°[Cc]\b"#, options: [])
  private static let temperatureSingularBareDegreeRegex = try! NSRegularExpression(pattern: #"(?<![\d.])1°"#, options: [])
  private static let temperatureFahrenheitRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)°[Ff]\b"#, options: [])
  private static let temperatureCelsiusRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)°[Cc]\b"#, options: [])
  private static let temperatureBareDegreeRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)°"#, options: [])

  /// Description of one temperature regex and the rewrite it performs.
  /// `expansionTemplate` is an NSRegularExpression replacement template;
  /// `lookupWordsFor(match:)` returns the post-rewrite token sequence the
  /// surface-preservation pass needs (with the matched number filled in).
  private struct TemperatureRule {
    let regex: NSRegularExpression
    let expansionTemplate: String
    /// The fixed words after the number, e.g. ["degrees", "Fahrenheit"].
    /// Combined with the captured number to produce `lookupWords`.
    let trailingWords: [String]
  }

  // Singular forms (no "s" on "degree") MUST run before the plural forms so
  // a literal "1°F" matches "1 degree" rather than the more permissive plural.
  // The capture group in every plural pattern is the full number; for the
  // singular patterns the captured text is always exactly "1".
  private static let temperatureRules: [TemperatureRule] = [
    TemperatureRule(regex: temperatureSingularFahrenheitRegex, expansionTemplate: "1 degree Fahrenheit", trailingWords: ["degree", "Fahrenheit"]),
    TemperatureRule(regex: temperatureSingularCelsiusRegex, expansionTemplate: "1 degree Celsius", trailingWords: ["degree", "Celsius"]),
    TemperatureRule(regex: temperatureSingularBareDegreeRegex, expansionTemplate: "1 degree", trailingWords: ["degree"]),
    TemperatureRule(regex: temperatureFahrenheitRegex, expansionTemplate: "$1 degrees Fahrenheit", trailingWords: ["degrees", "Fahrenheit"]),
    TemperatureRule(regex: temperatureCelsiusRegex, expansionTemplate: "$1 degrees Celsius", trailingWords: ["degrees", "Celsius"]),
    TemperatureRule(regex: temperatureBareDegreeRegex, expansionTemplate: "$1 degrees", trailingWords: ["degrees"]),
  ]

  static func normalizeTemperatures(_ text: String) -> String {
    applyTemperatureReplacements(to: text).text
  }

  /// Walk the input once, rewriting every temperature measurement and
  /// recording one SurfaceSubstitution per match. The surface-preservation
  /// pass in tokenize() uses these substitutions to put the original surface
  /// form (e.g. "110°F") back on the first NLTagger output token while
  /// emptying the display text on the trailing word tokens — so phoneme
  /// generation still produces "one hundred ten degrees Fahrenheit" but the
  /// chyron and the underline-highlighter see only "110°F".
  static func applyTemperatureReplacements(to text: String) -> (text: String, substitutions: [SurfaceSubstitution]) {
    struct PendingMatch {
      let originalRange: Range<String.Index>  // Full match in the original text
      let numberText: String                  // Captured number, e.g. "110" or "98.6"
      let rule: TemperatureRule
    }

    var pending: [PendingMatch] = []
    let nsRange = NSRange(text.startIndex..., in: text)

    for rule in temperatureRules {
      for match in rule.regex.matches(in: text, options: [], range: nsRange) {
        guard let originalRange = Range(match.range, in: text) else { continue }
        // Skip if any earlier-priority rule already matched this region. The
        // singular rules come first in `temperatureRules`, so this preserves
        // the existing "1°F" → "1 degree Fahrenheit" behavior even though
        // the plural pattern would also match "1°F".
        if pending.contains(where: { $0.originalRange.overlaps(originalRange) }) { continue }
        let numberText: String
        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
          numberText = String(text[r])
        } else {
          // Singular patterns have no capture group; the matched number is "1".
          numberText = "1"
        }
        pending.append(PendingMatch(originalRange: originalRange, numberText: numberText, rule: rule))
      }
    }

    pending.sort(by: { $0.originalRange.lowerBound < $1.originalRange.lowerBound })

    var result = ""
    var substitutions: [SurfaceSubstitution] = []
    var lastEnd = text.startIndex

    for match in pending {
      result.append(contentsOf: text[lastEnd..<match.originalRange.lowerBound])

      let originalSurface = String(text[match.originalRange])
      let expansion = "\(match.numberText) \(match.rule.trailingWords.joined(separator: " "))"
      let lookupWords = [match.numberText] + match.rule.trailingWords

      let modifiedStartUTF16 = (result as NSString).length
      result.append(expansion)
      let modifiedEndUTF16 = (result as NSString).length

      substitutions.append(SurfaceSubstitution(
        originalText: originalSurface,
        lookupWords: lookupWords,
        modifiedNSRange: NSRange(location: modifiedStartUTF16, length: modifiedEndUTF16 - modifiedStartUTF16)
      ))

      lastEnd = match.originalRange.upperBound
    }

    result.append(contentsOf: text[lastEnd..<text.endIndex])

    return (text: result, substitutions: substitutions)
  }

  // Period-terminated abbreviations the lexicon doesn't know how to pronounce.
  // The lexicon has entries for Dr/Mr/Mrs but not these, and getSpecialCase()
  // only recognizes the *internal*-period acronym pattern (e.g. M.R.C.S.), so
  // tokens like "Jr." fall through to getNNP() which spells them letter-by-
  // letter — "Jr." comes out as "jay-arr" (sounds like "geez"), "Inc." comes
  // out garbled. Expanding to a real word at preprocessing time sidesteps
  // tokenization, POS-tagging, and lexicon-fallback fragility entirely.
  //
  // Each pattern requires a literal trailing period, so prefix collisions
  // (e.g. "Co" vs "Col", "Cpl") can't fire — the period anchor disambiguates.
  //
  // Period handling: NLTagger has built-in knowledge that "Mr."/"Dr." are
  // abbreviations and doesn't break a sentence on their period. Once we
  // substitute the abbreviation for a regular word, that hint is gone — a
  // preserved period after "Reverend" or "Captain" mid-sentence would be read
  // as a sentence terminator and produce an unnatural pause. So:
  //   • At end of input the original period doubles as the sentence terminator
  //     (and dropping it would lose the final-utterance prosody) — keep it.
  //   • Anywhere else the period was just an abbreviation marker — drop it.
  //
  // Surface-text preservation: the substitution is later "undone" at the
  // MToken level — see applyAbbreviationAliases(...). Each AbbreviationSubstitution
  // remembers the original abbreviation letters and where the expansion now
  // sits in the modified text, so tokenize() can restore token.text to the
  // original ("Jr.") while leaving _.alias = expansion ("Junior") for lexicon
  // lookup. This keeps the chyron and the underline-highlighter (both of which
  // search the original input string) working correctly.
  private static let abbreviations: [(abbrev: String, expansion: String)] = [
    // Name suffixes
    ("Jr", "Junior"),
    ("Sr", "Senior"),
    ("Esq", "Esquire"),
    // Company designations
    ("Inc", "Ink"),
    ("Ltd", "Limited"),
    ("Corp", "Corporation"),
    ("Co", "Company"),
    // Civilian titles
    ("Hon", "Honorable"),
    ("Gov", "Governor"),
    ("Sen", "Senator"),
    ("Rep", "Representative"),
    ("Pres", "President"),
    ("Sec", "Secretary"),
    ("Rev", "Reverend"),
    ("Fr", "Father"),
    // Military ranks
    ("Gen", "General"),
    ("Lt", "Lieutenant"),
    ("Col", "Colonel"),
    ("Maj", "Major"),
    ("Capt", "Captain"),
    ("Sgt", "Sergeant"),
    ("Cpl", "Corporal"),
    ("Pvt", "Private"),
  ]

  private static let endOfInputAbbreviationRegexes: [(abbrev: String, expansion: String, regex: NSRegularExpression)] = abbreviations.map { (abbrev, expansion) in
    (abbrev, expansion, try! NSRegularExpression(pattern: "(?i)\\b\(abbrev)\\.(?=\\s*$)", options: []))
  }

  private static let midSentenceAbbreviationRegexes: [(abbrev: String, expansion: String, regex: NSRegularExpression)] = abbreviations.map { (abbrev, expansion) in
    (abbrev, expansion, try! NSRegularExpression(pattern: "(?i)\\b\(abbrev)\\.", options: []))
  }

  /// Tracks one preprocessing rewrite (e.g. `"Jr."` → `"Junior"`, or `"110°F"`
  /// → `"110 degrees Fahrenheit"`). Used after tokenization to restore
  /// `token.text` to the original surface form (so the kokoro app's chyron
  /// renders the user's input verbatim and `text.range(of: token.text)` still
  /// finds the token in the original transcript) while leaving the expansion
  /// in `_.alias`/sibling tokens so the lexicon path produces the right
  /// phonemes.
  ///
  /// The 1:1 case (abbreviations) has a single-element `lookupWords`. The
  /// 1:N case (temperatures) has one element per word in the expansion —
  /// the first covered token displays the original surface and looks up
  /// `lookupWords[0]`; the remaining covered tokens are display-suppressed
  /// (text/whitespace cleared) but each still looks up its own word so the
  /// audio plays the full expansion.
  struct SurfaceSubstitution {
    /// What the user typed (e.g. `"Jr."`, `"Inc"`, `"110°F"`). For mid-
    /// sentence abbreviations this includes the dropped trailing period;
    /// for end-of-input abbreviations and for temperatures it does not (the
    /// trailing period in those cases is its own token outside the
    /// substitution range).
    let originalText: String
    /// The expansion split into one entry per token NLTagger will produce
    /// from the rewritten text, in order. E.g. `["Junior"]` for `"Jr."` →
    /// `"Junior"`, or `["110", "degrees", "Fahrenheit"]` for `"110°F"` →
    /// `"110 degrees Fahrenheit"`.
    let lookupWords: [String]
    /// Where the expansion now sits in the post-rewrite text. Stored as
    /// NSRange (UTF-16 offsets) rather than Range<String.Index> because the
    /// downstream `result` string in preprocess() is a separate String
    /// instance, and NSRange survives that boundary while String.Index does
    /// not. Token ranges come back as Range<String.Index> from NLTagger but
    /// convert losslessly to NSRange against the same text.
    let modifiedNSRange: NSRange
  }

  static func normalizeAbbreviations(_ text: String) -> String {
    applyAbbreviationReplacements(to: text).text
  }

  /// Combined preprocessing pass that runs every surface rewrite (currently
  /// temperatures + abbreviations) against the *original* input in one go.
  /// Doing both passes together — rather than chaining the two helpers —
  /// keeps every recorded `modifiedNSRange` in the same coordinate space (the
  /// final result text). Chaining would corrupt the first pass's positions
  /// any time the second pass shifted text earlier in the buffer (e.g.
  /// "Capt. Smith said it was 110°F" would get the temperature substitution
  /// recorded against the post-temperature text, but the subsequent "Capt."
  /// → "Captain" rewrite shifts everything after by +2, leaving the
  /// temperature substitution pointing two characters too early).
  ///
  /// The standalone `applyTemperatureReplacements` and
  /// `applyAbbreviationReplacements` helpers remain (they're useful for unit
  /// tests that want to exercise one rewrite family in isolation), but
  /// `preprocess()` calls only this combined function.
  static func applyAllReplacements(to text: String) -> (text: String, substitutions: [SurfaceSubstitution]) {
    struct PendingRewrite {
      let originalRange: Range<String.Index>      // Span of the rewritten text in `text`
      let originalSurfaceText: String              // Goes into SurfaceSubstitution.originalText
      let expansion: String                        // Written to result for the substitution
      let lookupWords: [String]                    // Goes into SurfaceSubstitution.lookupWords
      let trailingChar: String                     // "" or "." (for end-of-input abbreviations)
    }

    var pending: [PendingRewrite] = []
    let nsRange = NSRange(text.startIndex..., in: text)

    // Temperature matches first. Singular variants are listed before plural
    // in `temperatureRules` so the overlap-skip below preserves the existing
    // "1°F" → "1 degree Fahrenheit" priority.
    for rule in temperatureRules {
      for match in rule.regex.matches(in: text, options: [], range: nsRange) {
        guard let originalRange = Range(match.range, in: text) else { continue }
        if pending.contains(where: { $0.originalRange.overlaps(originalRange) }) { continue }
        let numberText: String
        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
          numberText = String(text[r])
        } else {
          numberText = "1"
        }
        let lookupWords = [numberText] + rule.trailingWords
        pending.append(PendingRewrite(
          originalRange: originalRange,
          originalSurfaceText: String(text[originalRange]),
          expansion: lookupWords.joined(separator: " "),
          lookupWords: lookupWords,
          trailingChar: ""
        ))
      }
    }

    // End-of-input abbreviations next (they want to keep the trailing period
    // as a sentence terminator, so they need to win over the mid-sentence
    // pattern when both match at the same position).
    for (abbrev, expansion, regex) in endOfInputAbbreviationRegexes {
      for match in regex.matches(in: text, options: [], range: nsRange) {
        guard let entireRange = Range(match.range, in: text) else { continue }
        if pending.contains(where: { $0.originalRange.overlaps(entireRange) }) { continue }
        let abbrevEnd = text.index(entireRange.lowerBound, offsetBy: abbrev.count)
        let abbrevRange = entireRange.lowerBound..<abbrevEnd
        pending.append(PendingRewrite(
          originalRange: entireRange,
          originalSurfaceText: String(text[abbrevRange]),  // letters only — period preserved as separate token
          expansion: expansion,
          lookupWords: [expansion],
          trailingChar: "."
        ))
      }
    }

    // Mid-sentence abbreviations last.
    for (_, expansion, regex) in midSentenceAbbreviationRegexes {
      for match in regex.matches(in: text, options: [], range: nsRange) {
        guard let entireRange = Range(match.range, in: text) else { continue }
        if pending.contains(where: { $0.originalRange.overlaps(entireRange) }) { continue }
        pending.append(PendingRewrite(
          originalRange: entireRange,
          originalSurfaceText: String(text[entireRange]),  // includes the period (no separate "." token follows)
          expansion: expansion,
          lookupWords: [expansion],
          trailingChar: ""
        ))
      }
    }

    pending.sort(by: { $0.originalRange.lowerBound < $1.originalRange.lowerBound })

    var result = ""
    var substitutions: [SurfaceSubstitution] = []
    var lastEnd = text.startIndex

    for match in pending {
      result.append(contentsOf: text[lastEnd..<match.originalRange.lowerBound])

      let modifiedStartUTF16 = (result as NSString).length
      result.append(match.expansion)
      let modifiedEndUTF16 = (result as NSString).length

      substitutions.append(SurfaceSubstitution(
        originalText: match.originalSurfaceText,
        lookupWords: match.lookupWords,
        modifiedNSRange: NSRange(location: modifiedStartUTF16, length: modifiedEndUTF16 - modifiedStartUTF16)
      ))

      result.append(match.trailingChar)
      lastEnd = match.originalRange.upperBound
    }

    result.append(contentsOf: text[lastEnd..<text.endIndex])

    return (text: result, substitutions: substitutions)
  }

  /// Walk the input once, rewriting every period-terminated abbreviation and
  /// recording a SurfaceSubstitution for each. The two stages (end-of-
  /// input vs mid-sentence) collide on the same abbreviation token if the text
  /// happens to end with one — in that case the end-of-input variant wins so
  /// the trailing period is preserved as a sentence terminator.
  static func applyAbbreviationReplacements(to text: String) -> (text: String, substitutions: [SurfaceSubstitution]) {
    struct PendingMatch {
      let abbreviationRange: Range<String.Index>  // Just the abbrev letters in `text`
      let entireRange: Range<String.Index>         // Letters + the trailing period
      let expansion: String
      let keepPeriod: Bool
    }

    var pending: [PendingMatch] = []
    let nsRange = NSRange(text.startIndex..., in: text)

    for (abbrev, expansion, regex) in endOfInputAbbreviationRegexes {
      for match in regex.matches(in: text, options: [], range: nsRange) {
        guard let entireRange = Range(match.range, in: text) else { continue }
        let abbrevEnd = text.index(entireRange.lowerBound, offsetBy: abbrev.count)
        pending.append(PendingMatch(
          abbreviationRange: entireRange.lowerBound..<abbrevEnd,
          entireRange: entireRange,
          expansion: expansion,
          keepPeriod: true
        ))
      }
    }


    for (abbrev, expansion, regex) in midSentenceAbbreviationRegexes {
      for match in regex.matches(in: text, options: [], range: nsRange) {
        guard let entireRange = Range(match.range, in: text) else { continue }
        if pending.contains(where: { $0.entireRange.overlaps(entireRange) }) { continue }
        let abbrevEnd = text.index(entireRange.lowerBound, offsetBy: abbrev.count)
        pending.append(PendingMatch(
          abbreviationRange: entireRange.lowerBound..<abbrevEnd,
          entireRange: entireRange,
          expansion: expansion,
          keepPeriod: false
        ))
      }
    }

    pending.sort(by: { $0.entireRange.lowerBound < $1.entireRange.lowerBound })

    var result = ""
    var substitutions: [SurfaceSubstitution] = []
    var lastEnd = text.startIndex

    for match in pending {
      result.append(contentsOf: text[lastEnd..<match.entireRange.lowerBound])

      // For end-of-input cases the trailing period stays in the modified text
      // as its own token, so the originalText we hand back covers just the
      // abbreviation letters. For mid-sentence cases the period was dropped
      // (no separate "." token follows), so we fold the period into the
      // originalText — otherwise the chyron would render "Apple Inc is here"
      // without the period after "Inc", and the highlight would underline
      // only "Inc" instead of "Inc.".
      let originalAbbrevText: String
      if match.keepPeriod {
        originalAbbrevText = String(text[match.abbreviationRange])
      } else {
        originalAbbrevText = String(text[match.entireRange])
      }

      let modifiedStartUTF16 = (result as NSString).length
      result.append(match.expansion)
      let modifiedEndUTF16 = (result as NSString).length

      substitutions.append(SurfaceSubstitution(
        originalText: originalAbbrevText,
        lookupWords: [match.expansion],
        modifiedNSRange: NSRange(location: modifiedStartUTF16, length: modifiedEndUTF16 - modifiedStartUTF16)
      ))

      if match.keepPeriod {
        result.append(".")
      }

      lastEnd = match.entireRange.upperBound
    }

    result.append(contentsOf: text[lastEnd..<text.endIndex])

    return (text: result, substitutions: substitutions)
  }
  
  struct PreprocessFeature {
    enum Value {
      case int(Int)
      case double(Double)
      case string(String)
    }
    
    let value: Value
    let tokenRange: Range<String.Index>
  }

  public init(british: Bool = false, unk: String = "❓") {
    self.british = british
    self.tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
    self.lexicon = Lexicon(british: british)
    self.fallback = EnglishFallbackNetwork(british: british)
    self.unk = unk
  }

  private func tokenContext(_ ctx: TokenContext, ps: String?, token: MToken) -> TokenContext {
    var vowel = ctx.futureVowel
    
    if let ps = ps {
      for c in ps {
        if EnglishG2P.nonQuotePunctuations.contains(c) {
          vowel = nil
          break
        }
        
        if EnglishG2P.vowels.contains(c) {
          vowel = true
          break
        }
        
        if EnglishG2P.consonants.contains(c) {
          vowel = false
          break
        }
      }
    }
    let futureTo = (token.text == "to" || token.text == "To") || (token.text == "TO" && (token.tag == .particle || token.tag == .preposition))
    return TokenContext(futureVowel: vowel, futureTo: futureTo)
  }
  
  func stressWeight(_ phonemes: String?) -> Int {
    let dipthongs = Set("AIOQWYʤʧ")
    guard let phonemes else { return 0 }
    return phonemes.reduce(0) { sum, character in
      sum + (dipthongs.contains(character) ? 2 : 1)
    }
  }
  
  private func resolveTokens(_ tokens: inout [MToken]) {
    let text = tokens.dropLast().map { $0.text + $0.whitespace }.joined() + (tokens.last?.text ?? "")
    let prespace = text.contains(" ") || text.contains("/") || Set(text.compactMap { c -> Int? in
      if EnglishG2P.subTokenJunks.contains(c) { return nil }
      
      if c.isLetter { return 0 }
      if c.isNumber { return 1 }
      return 2
    }).count > 1
        
    for i in 0..<tokens.count {
      if tokens[i].phonemes == nil {
        if i == tokens.count - 1, let last = tokens[i].text.last, EnglishG2P.nonQuotePunctuations.contains(last) {
          tokens[i].phonemes = tokens[i].text
          tokens[i].`_`.rating = 3
        } else if tokens[i].text.allSatisfy({ EnglishG2P.subTokenJunks.contains($0) }) {
          tokens[i].phonemes = nil
          tokens[i].`_`.rating = 3
        }
      } else if i > 0 {
          tokens[i].`_`.prespace = prespace
      }
    }
    
    guard !prespace else { return }
    
    var indices: [(Bool, Int, Int)] = []
    for (i, tk) in tokens.enumerated() {
      if let ps = tk.phonemes, !ps.isEmpty {
        indices.append((ps.contains(Lexicon.primaryStress), stressWeight(ps), i))
      }
    }
    if indices.count == 2, tokens[indices[0].2].text.count == 1 {
        let i = indices[1].2
      tokens[i].phonemes = Lexicon.applyStress(tokens[i].phonemes, stress: -0.5)
        return
    } else if indices.count < 2 || indices.map({ $0.0 ? 1 : 0 }).reduce(0, +) <= (indices.count + 1) / 2 {
        return
    }
    indices.sort { ($0.0 ? 1 : 0, $0.1) < ($1.0 ? 1 : 0, $1.1) }
    let cut = indices.prefix(indices.count / 2)

    for x in cut {
      let i = x.2
      tokens[i].phonemes = Lexicon.applyStress(tokens[i].phonemes, stress: -0.5)
    }
  }
    
  // Text pre-processing tuple for easing the tokenization
  typealias PreprocessTuple = (text: String, tokens: [String], features: [PreprocessFeature], surfaceSubstitutions: [SurfaceSubstitution])
    
  /// Preprocesses the string in case there are some parts where the pronounciation or stress is pre-dictated using Markdown-like link format, e.g.
  /// "[Misaki](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models."
  private func preprocess(text: String) -> PreprocessTuple {
    // Matches the pattern of form [link text](url) and captures the two parts
    let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]*)\)"#, options: [])

    var result = ""
    var tokens: [String] = []
    var features: [PreprocessFeature] = []

    // Expand temperature measurements (e.g. "110°F") and period-terminated
    // abbreviations (e.g. "Jr.", "Inc.") into spoken form before tokenization,
    // so the degree symbol and unknown-abbreviation tokens don't derail the
    // phonemizer. The combined helper records every substitution so tokenize()
    // can later restore the original surface text on the resulting tokens —
    // the chyron and underline-highlighter both search the original input
    // for token.text.
    let rewritten = EnglishG2P.applyAllReplacements(
      to: text.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    let input = rewritten.text
    let surfaceSubstitutions = rewritten.substitutions
    var lastEnd = input.startIndex
    let ns = input as NSString
    let fullRange = NSRange(location: 0, length: ns.length)
 
    linkRegex.enumerateMatches(in: input, options: [], range: fullRange) { match, _, _ in
      guard let m = match else { return }

      let range = m.range
      let start = input.index(input.startIndex, offsetBy: range.location)
      let end = input.index(start, offsetBy: range.length)

      result += String(input[lastEnd..<start])
      tokens.append(contentsOf: String(input[lastEnd..<start]).split(separator: " ").map(String.init))

      let grapheme = ns.substring(with: m.range(at: 1))
      let phoneme = ns.substring(with: m.range(at: 2))
      
      let tokenStartIndex = result.endIndex
      result += grapheme
      let tokenRange = tokenStartIndex..<result.endIndex

      if let intValue = Int(phoneme) {
        features.append(PreprocessFeature(value: .int(intValue), tokenRange: tokenRange))
      } else if ["0.5", "+0.5"].contains(phoneme) {
        features.append(PreprocessFeature(value: .double(0.5), tokenRange: tokenRange))
      } else if phoneme == "-0.5" {
        features.append(PreprocessFeature(value: .double(-0.5), tokenRange: tokenRange))
      } else if phoneme.count > 1 && phoneme.first == "/" && phoneme.last == "/" {
        features.append(PreprocessFeature(value: .string(String(phoneme.dropLast())), tokenRange: tokenRange))
      } else if phoneme.count > 1 && phoneme.first == "#" && phoneme.last == "#" {
        features.append(PreprocessFeature(value: .string(String(phoneme.dropLast())), tokenRange: tokenRange))
      }

      tokens.append(grapheme)
      lastEnd = end
    }
    
    if lastEnd < input.endIndex {
      result += String(input[lastEnd...])
      tokens.append(contentsOf: String(input[lastEnd...]).split(separator: " ").map(String.init))
    }
    
    return (text: result, tokens: tokens, features: features, surfaceSubstitutions: surfaceSubstitutions)
  }

  private func tokenize(preprocessedText: PreprocessTuple) -> [MToken] {
    var mutableTokens: [MToken] = []
    
    // Tokenize and perform part-of-speech tagging
    tagger.string = preprocessedText.text
    tagger.setLanguage(.english, range: preprocessedText.text.startIndex..<preprocessedText.text.endIndex)
    let options: NLTagger.Options = []
    tagger.enumerateTags(
      in: preprocessedText.text.startIndex..<preprocessedText.text.endIndex,
      unit: .word,
      scheme: .nameTypeOrLexicalClass,
      options: options) { tag, tokenRange in
      if let tag = tag {
        let word = String(preprocessedText.text[tokenRange])
        if tag == .whitespace, let lastToken = mutableTokens.last {
          lastToken.whitespace = word
        } else {
          mutableTokens.append(MToken(text: word, tokenRange: tokenRange, tag: tag, whitespace: ""))
        }
      }
        
      return true
    }
                            
    // Simplistic alignment by index to add stress and pre-phonemization features to tokens
    // TO_DO: Doesn't match the capability of spacy.training.Alignment.from_strings()
    for feature in preprocessedText.features {
      for token in mutableTokens {
        if token.tokenRange.contains(feature.tokenRange) || feature.tokenRange.contains(token.tokenRange) {
          switch feature.value {
            case .int(let int):
              token.`_`.stress = Double(int)
            case .double(let double):
              token.`_`.stress = double
            case .string(let string):
              if string.hasPrefix("/") {
                token.`_`.is_head = true
                token.phonemes = String(string.dropFirst())
                token.`_`.rating = 5
              } else if string.hasPrefix("#") {
                token.`_`.num_flags = String(string.dropFirst())
              }
          }
        }
      }
    }

    // Restore original surface text on tokens that were rewritten during
    // preprocessing (abbreviations, temperatures, …). The first token in each
    // substitution's range gets `text = sub.originalText` (so the chyron and
    // the underline-highlighter both see the user's original input) and
    // `_.alias = sub.lookupWords[0]` (so the lexicon path looks up the right
    // word). For 1:N substitutions like "110°F" → "110 degrees Fahrenheit",
    // the trailing covered tokens are display-suppressed (text + whitespace
    // emptied) but each still gets its own `_.alias` so phoneme generation
    // produces the full spoken expansion. The first token absorbs the last
    // covered token's whitespace so concatenating `text + whitespace` over
    // the surviving tokens still produces the correct spacing.
    for sub in preprocessedText.surfaceSubstitutions {
      let coveredIndices = mutableTokens.indices.filter { i in
        let r = NSRange(mutableTokens[i].tokenRange, in: preprocessedText.text)
        return sub.modifiedNSRange.location <= r.location
          && r.location + r.length <= sub.modifiedNSRange.location + sub.modifiedNSRange.length
      }
      // Defensive: if NLTagger split the expansion differently than expected
      // (e.g. it tokenized "110 degrees Fahrenheit" into 4 word tokens
      // instead of 3), leave the tokens untouched so we don't garble the
      // output. assertionFailure flags it in debug builds.
      guard coveredIndices.count == sub.lookupWords.count, let firstIdx = coveredIndices.first else {
        assertionFailure("surface substitution covered \(coveredIndices.count) tokens but expected \(sub.lookupWords.count) for \(sub.originalText) -> \(sub.lookupWords)")
        continue
      }
      let lastIdx = coveredIndices.last!
      let stitchedWhitespace = mutableTokens[lastIdx].whitespace
      mutableTokens[firstIdx].text = sub.originalText
      mutableTokens[firstIdx].`_`.alias = sub.lookupWords[0]
      if firstIdx != lastIdx {
        mutableTokens[firstIdx].whitespace = stitchedWhitespace
      }
      for (offset, idx) in coveredIndices.enumerated() where offset > 0 {
        mutableTokens[idx].text = ""
        mutableTokens[idx].whitespace = ""
        mutableTokens[idx].`_`.alias = sub.lookupWords[offset]
      }
    }

    return mutableTokens
  }
  
  func mergeTokens(_ tokens: [MToken], unk: String? = nil) -> MToken {
    let stressSet = Set(tokens.compactMap { $0._.stress })
    let currencySet = Set(tokens.compactMap { $0._.currency })
    let ratings: Set<Int?> = Set(tokens.map { $0._.rating })
        
    var phonemes: String? = nil
    if let unk {
      var phonemeBuilder = ""
      for token in tokens {
        if token._.prespace,
           !phonemeBuilder.isEmpty,
           !(phonemeBuilder.last?.isWhitespace ?? false),
           token.phonemes != nil {
          phonemeBuilder += " "
        }
        phonemeBuilder += token.phonemes ?? unk
      }
      phonemes = phonemeBuilder
    }
    
    // Concatenate surface text and whitespace
    let mergedText = tokens.dropLast().map { $0.text + $0.whitespace }.joined() + (tokens.last?.text ?? "")

    // Choose tag from token with highest casing score
    func score(_ t: MToken) -> Int {
      return t.text.reduce(0) { $0 + (String($1) == String($1).lowercased() ? 1 : 2) }
    }
    let tagSource = tokens.max(by: { score($0) < score($1) })
    
    let tokenRangeStart = tokens.first!.tokenRange.lowerBound
    let tokenRangeEnd = tokens.last!.tokenRange.upperBound
    let flagChars = Set(tokens.flatMap { Array($0._.num_flags) })
    
    return MToken(
      text: mergedText,
      tokenRange: Range<String.Index>(uncheckedBounds: (lower: tokenRangeStart, upper: tokenRangeEnd)),
      tag: tagSource?.tag,
      whitespace: tokens.last?.whitespace ?? "",
      phonemes: phonemes,
      start_ts: tokens.first?.start_ts,
      end_ts: tokens.last?.end_ts,
      underscore: Underscore(
        is_head: tokens.first?._.is_head ?? false,
        alias: nil,
        stress: (stressSet.count == 1 ? stressSet.first : nil),
        currency: currencySet.max(),
        num_flags: String(flagChars.sorted()),
        prespace: tokens.first?._.prespace ?? false,
        rating: ratings.contains(where: { $0 == nil }) ? nil : ratings.compactMap { $0 }.min()
      )
    )
  }
    
  func foldLeft(_ tokens: [MToken]) -> [MToken] {
    var result: [MToken] = []
    for token in tokens {
      if let last = result.last, !token.`_`.is_head {
        _ = result.popLast()
        let merged = mergeTokens([last, token], unk: unk)
        result.append(merged)
      } else {
        result.append(token)
      }
    }
    return result
  }
  
  func subtokenize(word: String) -> [String] {
    let nsString = word as NSString
    let range = NSRange(location: 0, length: nsString.length)
    let matches = EnglishG2P.subtokenizeRegex.matches(in: word, options: [], range: range)
    
    return matches.map { match in
      nsString.substring(with: match.range)
    }
  }
  
  func retokenize(_ tokens: [MToken]) -> [Any] {
    var words: [Any] = []
    var currency: String? = nil
    
    for (i, token) in tokens.enumerated() {
      let needsSplit = (token.`_`.alias == nil && token.phonemes == nil)
      var subtokens: [MToken] = []
      if needsSplit {
        let parts = subtokenize(word: token.text)
        subtokens = parts.map { part in
          let t = MToken(copying: token)
          t.text = part
          t.whitespace = ""
          t.`_`.is_head = true
          t.`_`.prespace = false
          return t
        }
      } else {
        subtokens = [token]
      }
      subtokens.last?.whitespace = token.whitespace
          
      for j in 0..<subtokens.count {
        let token = subtokens[j]
      
        if token.`_`.alias != nil || token.phonemes != nil {
          // Do nothing at his point
        } else if token.tag == .otherWord, Lexicon.currencies[token.text] != nil {
          currency = token.text
          token.phonemes = ""
          token.`_`.rating = 4
        } else if token.tag == .dash || (token.tag == .punctuation && token.text == "–") {
          // Silence intra-word hyphens (e.g. "all-time") to prevent the
          // TTS engine from inserting an unnatural pause between the parts
          // of a compound word.  An intra-word hyphen is a plain "-" whose
          // preceding token has no trailing whitespace.
          let isIntraWordHyphen = token.text == "-" && i > 0 && tokens[i - 1].whitespace.isEmpty
          token.phonemes = isIntraWordHyphen ? "" : "—"
          token.`_`.rating = 3
        } else if let tag = token.tag, EnglishG2P.punctuationTags.contains(tag), !token.text.lowercased().unicodeScalars.allSatisfy({ (97...122).contains(Int($0.value)) }), Lexicon.symbolSet[token.text] == nil {
          if let val = EnglishG2P.punctuationTagPhonemes[token.text] {
            token.phonemes = val
          } else {
            token.phonemes = token.text.filter { EnglishG2P.punctuactions.contains($0) }
          }
          token.`_`.rating = 4
        } else if currency != nil {
          // NLTagger tags decimal amounts (e.g. "5.72" from "$5.72") as .otherWord
          // instead of .number. Accept tokens that look numeric regardless of tag.
          let looksNumeric = token.text.contains(where: { $0.isNumber }) &&
            token.text.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." })
          if token.tag != .number && !looksNumeric {
            currency = nil
          } else if j + 1 == subtokens.count && (i + 1 == tokens.count || tokens[i + 1].tag != .number) {
            token.`_`.currency = currency
          }
        } else if j > 0 && j < subtokens.count - 1 && token.text == "2" {
          let prev = subtokens[j - 1].text
          let next = subtokens[j + 1].text
          if (prev.last.map { String($0) } ?? "" + (next.first.map { String($0) } ?? "")).allSatisfy({ $0.isLetter }) ||
             (prev == "-" && next == "-") {
            token.`_`.alias = "to"
          }
        }
           
        if token.`_`.alias != nil || token.phonemes != nil {
          words.append(token)
        } else if let last = words.last as? [MToken], last.last?.whitespace.isEmpty == true {
          var arr = last
          token.`_`.is_head = false
          arr.append(token)
          _ = words.popLast()
          words.append(arr)
        } else {
          if token.whitespace.isEmpty { words.append([token]) } else { words.append(token) }
        }
      }
    }
                
    return words.map { item in
      if let arr = item as? [MToken], arr.count == 1 { return arr[0] }
      return item
    }
  }
   
  // Turns the text into phonemes that can then be fed to text-to-speech (TTS) engine for converting to audio
  public func phonemize(text: String, performPreprocess: Bool = true) -> (String, [MToken]) {
    let pre: PreprocessTuple
    if performPreprocess {
        pre = self.preprocess(text: text)
    } else {
        pre = (text: text, tokens: [], features: [], surfaceSubstitutions: [])
    }

    var tokens = tokenize(preprocessedText: pre)
    tokens = foldLeft(tokens)
    
    let words = retokenize(tokens)
    
    var ctx = TokenContext()
    for i in stride(from: words.count - 1, through: 0, by: -1) {
      if let w = words[i] as? MToken {
        if w.phonemes == nil {
          let out = lexicon.transcribe(w, ctx: ctx)
          w.phonemes = out.0
          w.`_`.rating = out.1
        }
        
        if w.phonemes == nil {
          let out = fallback(w)
          w.phonemes = out.0
          w.`_`.rating = out.1
        }
        
        ctx = tokenContext(ctx, ps: w.phonemes, token: w)
      } else if var arr = words[i] as? [MToken] {
        var left = 0
        var right = arr.count
        var shouldFallback = false
        while left < right {
          let hasFixed = arr[left..<right].contains { $0.`_`.alias != nil || $0.phonemes != nil }
          let token: MToken? = hasFixed ? nil : mergeTokens(Array(arr[left..<right]))
          let res: (String?, Int?) = (token == nil) ? (nil, nil) : lexicon.transcribe(token!, ctx: ctx)
          
          if let phonemes = res.0 {
            arr[left].phonemes = phonemes
            arr[left].`_`.rating = res.1
            for j in (left + 1)..<right {
              arr[j].phonemes = ""
              arr[j].`_`.rating = res.1
            }
            ctx = tokenContext(ctx, ps: phonemes, token: token!)
            right = left
            left = 0
          } else if left + 1 < right {
            left += 1
          } else {
            right -= 1
            let last = arr[right]
            if last.phonemes == nil {
              if last.text.allSatisfy({ EnglishG2P.subTokenJunks.contains($0) }) {
                last.phonemes = ""
                last.`_`.rating = 3
              } else {
                shouldFallback = true
                break
              }
            }
            left = 0
            arr[right] = last
          }
        }
        
        if shouldFallback {
          let token = mergeTokens(arr)
          let first = arr[0]
          let out = fallback(token)
          first.phonemes = out.0
          first.`_`.rating = out.1
          arr[0] = first
          if arr.count > 1 {
            for j in 1..<arr.count {
              arr[j].phonemes = ""
              arr[j].`_`.rating = out.1
            }
          }
        } else {
          resolveTokens(&arr)
        }
      }
    }
    
    let finalTokens: [MToken] = words.map { item in
      if let arr = item as? [MToken] { return mergeTokens(arr, unk: self.unk) }
      return item as! MToken
    }
        
    for i in 0..<finalTokens.count {
      if var ps = finalTokens[i].phonemes, !ps.isEmpty {
        ps = ps.replacingOccurrences(of: "ɾ", with: "T").replacingOccurrences(of: "ʔ", with: "t")
        finalTokens[i].phonemes = ps
      }
    }

    let result = finalTokens.map { ( $0.phonemes ?? self.unk ) + $0.whitespace }.joined()
    return (result, finalTokens)
  }
}
