import Testing
import Foundation
import NaturalLanguage
import MLXUtilsLibrary
@testable import MisakiSwift

// MARK: - Dictionary-driven word segmentation (pure; CLI-safe)
//
// Naming is load-bearing: pure tests are prefixed testWordSegmentation_ so
// the CLI filter `swift test --filter testWordSegmentation_` runs only the
// phonemize-free tests; the full-pipeline tests use
// testWordSegmentationPhonemize_ and need Xcode/xcodebuild (CLI swift test
// crashes on the MLX metallib).

@Test func testWordSegmentation_SplitsConcatenations() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "binaryteaparty") == ["binary", "tea", "party"])
  #expect(lexicon.segmentation(of: "textgoeshear") == ["text", "goes", "hear"])
  #expect(lexicon.segmentation(of: "youtube") == ["you", "tube"])
}

// Scoring prefers fewer, longer fragments.
@Test func testWordSegmentation_PrefersLongestFragments() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "stackoverflow") == ["stack", "overflow"])
}

// At most one 1–2 letter fragment, only at an edge: single letters spell,
// two-letter fragments come from the curated short-words set.
@Test func testWordSegmentation_EdgeShortFragments() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "gdrive") == ["g", "drive"])
  #expect(lexicon.segmentation(of: "icloud") == ["i", "cloud"])
  #expect(lexicon.segmentation(of: "ebay") == ["e", "bay"])
  #expect(lexicon.segmentation(of: "gopro") == ["go", "pro"])
}


// Words the dictionary can't fully explain fall through to the fallback
// network unchanged. "linkedin" documents a known gap: "linked" (inflected)
// has no gold entry, so it stays a fallback word for now.
@Test func testWordSegmentation_RefusesUnknownCoverage() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "misaki") == nil)
  #expect(lexicon.segmentation(of: "kokoro") == nil)
  #expect(lexicon.segmentation(of: "recieve") == nil)
  #expect(lexicon.segmentation(of: "linkedin") == nil)
}

@Test func testWordSegmentation_RefusesCasingLengthAndSymbols() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "Binaryteaparty") == nil)
  #expect(lexicon.segmentation(of: "tea") == nil)
  #expect(lexicon.segmentation(of: "route66") == nil)
  #expect(lexicon.segmentation(of: "e-mail") == nil)
  #expect(lexicon.segmentation(of: String(repeating: "tea", count: 10)) == nil)
}

// A single-fragment cover means the word was a dictionary word all along —
// never "segment" it (in practice transcribe() resolves it first). "gmail"
// and "georeference" pin the fused-gold-entry interplay: their entries
// outrank the g+mail and geo+reference splits.
@Test func testWordSegmentation_RequiresMultipleFragments() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "party") == nil)
  #expect(lexicon.segmentation(of: "gmail") == nil)
  #expect(lexicon.segmentation(of: "georeference") == nil)
}

// Fragments keep their gold stress; a leading letter name is demoted to
// secondary so the following word carries the beat.
@Test func testWordSegmentation_PhonemeJoin() async throws {
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentedPhonemes(of: "binaryteaparty").0 == "bˈInəɹi tˈi pˈɑɹɾi")
  #expect(lexicon.segmentedPhonemes(of: "gdrive").0 == "ʤˌi dɹˈIv")
  #expect(lexicon.segmentedPhonemes(of: "misaki").0 == nil)
}

private func transcribeWord(_ text: String, british: Bool, tag: NLTag? = .noun) -> String? {
  let lexicon = Lexicon(british: british)
  let token = MToken(text: text, tokenRange: text.startIndex..<text.endIndex, tag: tag, whitespace: "")
  return lexicon.transcribe(token, ctx: TokenContext()).0
}

// "georeference" (an alpha-tester report) was in no dictionary, and "geo"
// wasn't a US word either, so the compound could neither resolve nor segment
// and fell to the fallback network as one long garble. It now rides a fused
// gold entry composed like its gold siblings geolocation/geospatial
// (secondary-stressed geo prefix, primary stress on the head word), and the
// stemmers pick up its inflections from the base entry.
@Test func testWordSegmentation_GeoreferenceGoldEntry() async throws {
  #expect(transcribeWord("georeference", british: false) == "ʤˌiOɹˈɛfəɹəns")
  #expect(transcribeWord("georeference", british: true) == "ʤˌiːQɹˈɛfəɹəns")
  #expect(transcribeWord("georeferences", british: false) == "ʤˌiOɹˈɛfəɹənsᵻz")
  #expect(transcribeWord("georeferenced", british: false) == "ʤˌiOɹˈɛfəɹənst")
  #expect(transcribeWord("georeferencing", british: false) == "ʤˌiOɹˈɛfəɹənsɪŋ")
}

// "geo" is now a US word in its own right (gb_gold already had it): it
// appears standalone in prose, and it lets geo-compounds without their own
// entries (georadar) degrade to a segmented "geo X" instead of fallback
// garble — while compounds that do have entries (geofence) still resolve
// whole via the single-fragment rule.
@Test func testWordSegmentation_GeoUnlocksCompounds() async throws {
  #expect(transcribeWord("geo", british: false) == "ʤˈiO")
  let lexicon = Lexicon(british: false)
  #expect(lexicon.segmentation(of: "georadar") == ["geo", "radar"])
  #expect(lexicon.segmentation(of: "geofence") == nil)
}

// MARK: - Full-pipeline tests (Xcode/xcodebuild only — MLX metallib crashes
// under CLI `swift test`)

@Test func testWordSegmentationPhonemize_EmailDomain() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "Email josh@binaryteaparty.com now.")
  let (result, _) = englishG2P.phonemize(text: spoken)
  #expect(result.contains("bˈInəɹi tˈi pˈɑɹTi dˈɑt kˈɑm"))
}

// The transcript/chyron contract: the token keeps its run-together surface
// text while its phonemes carry the segmented words.
@Test func testWordSegmentationPhonemize_SurfaceTextVerbatim() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "Email josh@binaryteaparty.com now.")
  let (_, tokens) = englishG2P.phonemize(text: spoken)
  let token = tokens.first { $0.text == "binaryteaparty" }
  #expect(token != nil)
  #expect(token?.phonemes?.contains(" ") == true)
}

// "gmail" rides its fused gold entry ("gee-mail" as one word), which beats
// the g+mail segmentation; the capitalized prose form works via the
// dictionary's automatic case variants.
@Test func testWordSegmentationPhonemize_GmailGoldEntry() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Check your gmail inbox today.")
  #expect(result.contains("ʤˌimˈAl"))
  let (capitalized, _) = englishG2P.phonemize(text: "Check your Gmail inbox today.")
  #expect(capitalized.contains("ʤˌimˈAl"))
}

// "georeference" rides its fused gold entry like its gold siblings
// geolocation and geospatial; inflected prose resolves through the stemmers
// and the capitalized form through the automatic case variants.
@Test func testWordSegmentationPhonemize_GeoreferenceGoldEntry() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The map was georeferenced last week.")
  #expect(result.contains("ʤˌiOɹˈɛfəɹənst"))
  let (capitalized, _) = englishG2P.phonemize(text: "Georeference the scanned map first.")
  #expect(capitalized.contains("ʤˌiOɹˈɛfəɹəns"))
}

