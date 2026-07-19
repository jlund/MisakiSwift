import Testing
import Foundation
import NaturalLanguage
import MLXUtilsLibrary
@testable import MisakiSwift

// MARK: - Accented Latin handling (Nariño, café, résumé)
//
// Naming is load-bearing: pure tests are prefixed testAccented_ so the CLI
// filter `swift test --filter testAccented_` runs only the phonemize-free
// tests; the full-pipeline tests use testAccentedPhonemize_ and need
// Xcode/xcodebuild (CLI swift test crashes on the MLX metallib).

private func transcribeWord(_ text: String, british: Bool, tag: NLTag? = .noun) -> String? {
  let lexicon = Lexicon(british: british)
  let token = MToken(text: text, tokenRange: text.startIndex..<text.endIndex, tag: tag, whitespace: "")
  return lexicon.transcribe(token, ctx: TokenContext()).0
}

// Spelling-oriented folding feeds dictionary lookups: it must produce the
// conventional English respelling, including letters that have no Unicode
// decomposition (ß, ł, œ) and therefore survive .diacriticInsensitive.
@Test func testAccented_FoldedSpelling() async throws {
  #expect(AccentedLatin.foldedSpelling("café") == "cafe")
  #expect(AccentedLatin.foldedSpelling("Zürich") == "Zurich")
  #expect(AccentedLatin.foldedSpelling("façade") == "facade")
  #expect(AccentedLatin.foldedSpelling("Nariño") == "Narino")
  #expect(AccentedLatin.foldedSpelling("Straße") == "Strasse")
  #expect(AccentedLatin.foldedSpelling("Łódź") == "Lodz")
  #expect(AccentedLatin.foldedSpelling("Nguyễn") == "Nguyen")
  #expect(AccentedLatin.foldedSpelling("œuvre") == "oeuvre")
  #expect(AccentedLatin.foldedSpelling("Ångström") == "Angstrom")
}

// Fallback-network respelling favors pronunciation over spelling: ñ keeps its
// palatal glide and ç its soft sound.
@Test func testAccented_FallbackRespelling() async throws {
  #expect(AccentedLatin.fallbackRespelling("Nariño") == "Narinyo")
  #expect(AccentedLatin.fallbackRespelling("Núñez") == "Nunyez")
  #expect(AccentedLatin.fallbackRespelling("Besançon") == "Besanson")
  #expect(AccentedLatin.fallbackRespelling("Curaçao") == "Curasao")
  #expect(AccentedLatin.fallbackRespelling("jalapeño") == "jalapenyo")
  #expect(AccentedLatin.fallbackRespelling("Gijón") == "Gijon")
}

// ASCII words pass through untouched, and non-Latin scripts are deliberately
// out of scope — they keep today's unknown-token behavior downstream.
@Test func testAccented_RespellingPassthrough() async throws {
  #expect(AccentedLatin.fallbackRespelling("already-ascii") == "already-ascii")
  #expect(AccentedLatin.fallbackRespelling("Москва") == "Москва")
  #expect(AccentedLatin.fallbackRespelling("東京") == "東京")
}

// OCR and pasted text can arrive in decomposed (NFD) form; Swift Characters
// compare canonically, so n + combining tilde must behave exactly like ñ.
@Test func testAccented_DecomposedInput() async throws {
  let decomposed = "Nari\u{006E}\u{0303}o"
  #expect(AccentedLatin.fallbackRespelling(decomposed) == "Narinyo")
  #expect(AccentedLatin.foldedSpelling(decomposed) == "Narino")
}

// Every curated entry must stay inside its dialect's phoneme vocabulary —
// this catches typos in the hand-written phoneme strings.
@Test func testAccented_LoanwordsWithinDialectVocabularies() async throws {
  for (word, phonemes) in AccentedLatin.loanwords {
    #expect(phonemes.us.allSatisfy { Lexicon.usVocab.contains($0) },
            "US phonemes for \(word) stray outside usVocab")
    #expect(phonemes.gb.allSatisfy { Lexicon.gbVocab.contains($0) },
            "GB phonemes for \(word) stray outside gbVocab")
  }
}

// Folding lands common loanwords on their real dictionary entries.
@Test func testAccented_FoldedWordsHitDictionary() async throws {
  #expect(transcribeWord("café", british: false) == "kæfˈA")
  #expect(transcribeWord("café", british: true) == "kˈafA")
  #expect(transcribeWord("Café", british: false) == "kæfˈA")
  #expect(transcribeWord("naïve", british: false) == "nɑˈiv")
  #expect(transcribeWord("façade", british: false) == "fəsˈɑd")
  #expect(transcribeWord("purée", british: false) == "pjʊɹˈA")
}

// Words where folding would collide with a different English word resolve
// through the curated table instead ("résumé" must not say "rih-ZOOM").
@Test func testAccented_CuratedLoanwords() async throws {
  #expect(transcribeWord("résumé", british: false) == "ɹˈɛzəmˌA")
  #expect(transcribeWord("résumé", british: true) == "ɹˈɛzjʊmˌA")
  #expect(transcribeWord("Résumé", british: false) == "ɹˈɛzəmˌA")
  #expect(transcribeWord("RÉSUMÉ", british: false) == "ɹˈɛzəmˌA")
  #expect(transcribeWord("jalapeño", british: false) == "hˌɑləpˈAnjO")
  #expect(transcribeWord("rosé", british: false) == "ɹOzˈA")
  #expect(transcribeWord("Niño", british: false) == "nˈinjO")
}

// The unaccented spellings keep their ordinary dictionary pronunciations.
@Test func testAccented_PlainSpellingsUnaffected() async throws {
  #expect(transcribeWord("resume", british: false, tag: .verb) == "ɹəzˈum")
  #expect(transcribeWord("rose", british: false) == "ɹˈOz")
  #expect(transcribeWord("expose", british: false, tag: .verb) == "ɪkspˈOz")
}

// Accented words with no dictionary entry even after folding must return nil
// here so they reach the fallback network (which respells them itself).
@Test func testAccented_UnknownProperNounFallsThrough() async throws {
  #expect(transcribeWord("Nariño", british: false) == nil)
  #expect(transcribeWord("Gijón", british: false) == nil)
}

// MARK: - Full-pipeline tests (xcodebuild only)

// The tester-reported regression: "Nariño" reached the BART fallback as
// Nari<unk>o and came back as garble ("Neeraso"). Respelled as "Narinyo",
// the model now says nah-REE-nee-oh (it renders the palatal glide as an i in
// hiatus rather than j — both are acceptable; the garble is what mattered).
// Greedy decode over in-repo weights is deterministic, so the prefix is
// stable; revisit only if the BART weights are retrained.
@Test func testAccentedPhonemize_NarinoUsesFallbackRespelling() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Nariño")
  print("PHONEMIZE Nariño (US): \(result)")
  #expect(result.contains("nɑɹˈini"))
}

// Loanwords inside a real sentence resolve via the curated table and the
// folded dictionary lookup.
@Test func testAccentedPhonemize_LoanwordsInSentence() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Her résumé mentioned the café.")
  print("PHONEMIZE résumé/café (US): \(result)")
  #expect(result.contains("ɹˈɛzəmˌA"))
  #expect(result.contains("kæfˈA"))
}

// The exact sentence from the alpha-tester report.
@Test func testAccentedPhonemize_TesterSentence() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "High above Puerres, Nariño the team braved relentless rain")
  print("PHONEMIZE tester sentence (US): \(result)")
  #expect(result.contains("nɑɹˈini"))
  #expect(!result.isEmpty)
}

@Test func testAccentedPhonemize_BritishLoanwords() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "A jalapeño with rosé.")
  print("PHONEMIZE jalapeño/rosé (GB): \(result)")
  #expect(result.contains("hˌaləpˈAnjQ"))
  #expect(result.contains("ɹˈQzA"))
}
