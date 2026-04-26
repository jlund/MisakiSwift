import Testing
@testable import MisakiSwift

let texts: [(originalText: String, britishPhonetization: String, americanPhoneitization: String)] = [
  ("[Misaki](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models.",
   "misˈɑki ɪz ɐ ʤˈiːtəpˈiː ˈɛnʤɪn dɪzˈInd fɔː kˈOkəɹO mˈɒdᵊlz.",
   "misˈɑki ɪz ɐ ʤˈitəpˈi ˈɛnʤən dəzˈInd fɔɹ kˈOkəɹO mˈɑdᵊlz."),
  ("“To James Mortimer, M.R.C.S., from his friends of the C.C.H.,” was engraved upon it, with the date “1884.”",
   "“tə ʤˈAmz mˈɔːtɪmə, ˌɛmˌɑːsˌiːˈɛs, fɹɒm hɪz fɹˈɛndz ɒv ðə sˌiːsˌiːˈAʧ,” wɒz ɪnɡɹˈAvd əpˈɒn ɪt, wɪð ðə dˈAt “ˌAtˈiːn ˈAti fˈɔː.”",
   "“tə ʤˈAmz mˈɔɹTəməɹ, ˌɛmˌɑɹsˌiˈɛs, fɹʌm hɪz fɹˈɛndz ʌv ðə sˌisˌiˈAʧ,” wʌz ɪnɡɹˈAvd əpˈɑn ɪt, wɪð ðə dˈAt “ˌAtˈin ˈATi fˈɔɹ.”")
]

@Test func testStrings_BritishPhonetization() async throws {
  let englishG2P = EnglishG2P(british: true)
  
  for pair in texts {
    #expect(englishG2P.phonemize(text: pair.0).0 == pair.1)
  }
}

@Test func testStrings_AmericanPhonetization() async throws {
  let englishG2P = EnglishG2P(british: false)

  for pair in texts {
    #expect(englishG2P.phonemize(text: pair.0).0 == pair.2)
  }
}

// Retokenize Currency Index Fix Tests
@Test func testRetokenize_CurrencyWithFollowingTokens() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "$50 is the price for this item")
  #expect(!result.isEmpty)
  #expect(result.contains("dˈɒlə"))  // "dollar" phoneme should be present
}

// Currency appearing mid-sentence with multiple tokens before and after
@Test func testRetokenize_CurrencyInMiddleOfSentence() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The total cost was $100 and we paid it yesterday")
  #expect(!result.isEmpty)
  #expect(result.contains("dˈɑləɹz"))  // American "dollar" phoneme
}

// Multiple currency symbols trigger the currency code path multiple times
@Test func testRetokenize_MultipleCurrenciesInText() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "I exchanged $200 for €150 at the bank today")
  #expect(!result.isEmpty)
  #expect(result.contains("dˈɒlə"))    // "dollar" phoneme
  #expect(result.contains("jˈʊəɹQz"))  // "euro" phoneme
}

// Decimal currency amounts (NLTagger tags these as OtherWord instead of Number)
@Test func testRetokenize_DecimalCurrencyAmount() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The price is $5.72 for that item.")
  #expect(result.contains("dˈɑləɹz"))  // "dollars" phoneme
  #expect(result.contains("sˈɛnts"))   // "cents" phoneme
}

@Test func testRetokenize_DecimalCurrencyPounds() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "It costs £9.99 per month.")
  #expect(result.contains("pˈWndz"))   // "pounds" phoneme
  #expect(result.contains("pˈɛns"))    // "pence" phoneme
}

@Test func testRetokenize_LargeDecimalCurrency() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "She earned $1,234.56 last week.")
  #expect(result.contains("dˈɑləɹz"))  // "dollars" phoneme
  #expect(result.contains("sˈɛnts"))   // "cents" phoneme
}

// Temperature measurements (e.g. "110°F") should be expanded into spoken form
// before tokenization rather than being passed through to the fallback network.
@Test func testTemperature_Fahrenheit() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The temperature was 110°F today.")
  #expect(result.contains("dəɡɹˈi"))   // "degree(s)" phoneme stem
  #expect(result.contains("fˈɛɹənhˌIt")) // "Fahrenheit" phoneme
}

@Test func testTemperature_Celsius() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Water boils at 100°C.")
  #expect(result.contains("dəɡɹˈi"))   // "degree(s)" phoneme stem
  #expect(result.contains("sˈɛlsiəs")) // "Celsius" phoneme
}

@Test func testTemperature_BareDegree() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The angle is 45° from vertical.")
  #expect(result.contains("dəɡɹˈi"))   // "degree(s)" phoneme stem
}

@Test func testTemperature_DecimalFahrenheit() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Normal body temperature is 98.6°F.")
  #expect(result.contains("dəɡɹˈi"))
  #expect(result.contains("fˈɛɹənhˌIt"))
}

@Test func testTemperature_NormalizationHelper() async throws {
  #expect(EnglishG2P.normalizeTemperatures("110°F") == "110 degrees Fahrenheit")
  #expect(EnglishG2P.normalizeTemperatures("30°C") == "30 degrees Celsius")
  #expect(EnglishG2P.normalizeTemperatures("45°") == "45 degrees")
  #expect(EnglishG2P.normalizeTemperatures("from 60°F to 80°F") == "from 60 degrees Fahrenheit to 80 degrees Fahrenheit")
  #expect(EnglishG2P.normalizeTemperatures("98.6°F") == "98.6 degrees Fahrenheit")
  // Singular: only an isolated "1" takes the singular form.
  #expect(EnglishG2P.normalizeTemperatures("1°F") == "1 degree Fahrenheit")
  #expect(EnglishG2P.normalizeTemperatures("1°C") == "1 degree Celsius")
  #expect(EnglishG2P.normalizeTemperatures("1°") == "1 degree")
  // Plural still applies for 11, 21, 0.1, etc.
  #expect(EnglishG2P.normalizeTemperatures("11°F") == "11 degrees Fahrenheit")
  #expect(EnglishG2P.normalizeTemperatures("21°C") == "21 degrees Celsius")
  #expect(EnglishG2P.normalizeTemperatures("0.1°F") == "0.1 degrees Fahrenheit")
}

@Test func testTemperature_SingularFahrenheit() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It dropped to 1°F overnight.")
  // Singular "degree" lacks the plural /z/ ending.
  #expect(result.contains("dəɡɹˈi"))
  #expect(!result.contains("dəɡɹˈiz"))
  #expect(result.contains("fˈɛɹənhˌIt"))
}

// Intra-word hyphens should not produce an em-dash pause
@Test func testIntraWordHyphen_NoPause() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Enthusiasm was at an all-time high.")
  // The phoneme string must NOT contain "—" between "all" and "time"
  #expect(!result.contains("—"))
}

@Test func testInterWordDash_StillPauses() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Hello — world.")
  // A spaced em-dash should still produce a pause
  #expect(result.contains("—"))
}

// Period-terminated abbreviations like "Jr." and "Inc." should be expanded
// to a real word at preprocessing time. Without this, the lexicon falls
// through to letter-by-letter spelling, producing garbled audio.
@Test func testAbbreviations_NormalizationHelper() async throws {
  // Mid-sentence position: drop the trailing period so the expanded word
  // (now a regular dictionary word, no longer recognized as an abbreviation)
  // doesn't introduce a fake sentence break and unnatural pause.
  #expect(EnglishG2P.normalizeAbbreviations("Harold Jones Jr. went home.") == "Harold Jones Junior went home.")
  #expect(EnglishG2P.normalizeAbbreviations("Apple Inc. is here.") == "Apple Ink is here.")
  #expect(EnglishG2P.normalizeAbbreviations("Acme Co. signed.") == "Acme Company signed.")
  #expect(EnglishG2P.normalizeAbbreviations("Globex Corp. opened.") == "Globex Corporation opened.")
  #expect(EnglishG2P.normalizeAbbreviations("Initech Ltd. closed.") == "Initech Limited closed.")
  #expect(EnglishG2P.normalizeAbbreviations("Gov. Newsom spoke.") == "Governor Newsom spoke.")
  #expect(EnglishG2P.normalizeAbbreviations("Sen. Warren and Rep. Lee spoke.") == "Senator Warren and Representative Lee spoke.")
  #expect(EnglishG2P.normalizeAbbreviations("Rev. Smith and Fr. Brown.") == "Reverend Smith and Father Brown.")
  #expect(EnglishG2P.normalizeAbbreviations("Capt. Kirk and Lt. Uhura.") == "Captain Kirk and Lieutenant Uhura.")
  #expect(EnglishG2P.normalizeAbbreviations("Col. Mustard, Sgt. Pepper.") == "Colonel Mustard, Sergeant Pepper.")

  // End-of-input position: keep the trailing period, since it doubles as
  // the sentence terminator and dropping it would lose final-utterance prosody.
  #expect(EnglishG2P.normalizeAbbreviations("Sammy Davis Sr.") == "Sammy Davis Senior.")
  #expect(EnglishG2P.normalizeAbbreviations("John Smith, Esq.") == "John Smith, Esquire.")
  #expect(EnglishG2P.normalizeAbbreviations("She works at Apple Inc.") == "She works at Apple Ink.")
  #expect(EnglishG2P.normalizeAbbreviations("She works at Apple Inc.   ") == "She works at Apple Ink.   ")
  #expect(EnglishG2P.normalizeAbbreviations("She works at Apple Inc.\n") == "She works at Apple Ink.\n")

  // Case-insensitive matching, capitalized replacement
  #expect(EnglishG2P.normalizeAbbreviations("APPLE INC.") == "APPLE Ink.")
  #expect(EnglishG2P.normalizeAbbreviations("apple inc.") == "apple Ink.")
  #expect(EnglishG2P.normalizeAbbreviations("jr.") == "Junior.")

  // No-op cases: bare letters without trailing period must not be rewritten,
  // since matching them would over-trigger on names that share the letters.
  #expect(EnglishG2P.normalizeAbbreviations("Jr without period") == "Jr without period")
  #expect(EnglishG2P.normalizeAbbreviations("Inc operating loss") == "Inc operating loss")

  // Mid-word matches must not fire. The longer real word "Junior" must not
  // be rewritten because its leading "Jr" is followed by "u", not ".".
  #expect(EnglishG2P.normalizeAbbreviations("She is a Junior at school.") == "She is a Junior at school.")

  // Existing internal-period acronyms must be untouched (handled separately
  // by the lexicon's getSpecialCase).
  #expect(EnglishG2P.normalizeAbbreviations("M.R.C.S.") == "M.R.C.S.")
  #expect(EnglishG2P.normalizeAbbreviations("Mr. Smith") == "Mr. Smith")
}

@Test func testAbbreviations_JuniorEndToEnd() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Harold Jones Jr. went to the store.")
  // Must contain the "junior" phoneme, not letter-by-letter J-R spelling.
  #expect(result.contains("ʤˈunjəɹ"))
  // Mid-sentence: "Junior" must not be followed by a period in the phoneme
  // output, otherwise downstream prosody inserts a fake sentence break.
  #expect(!result.contains("ʤˈunjəɹ."))
}

@Test func testAbbreviations_IncEndToEnd() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Apple Inc. is a valuable company.")
  // Must contain the "ink" phoneme, not garbled fallback output.
  #expect(result.contains("ˈɪŋk"))
  // Mid-sentence: no fake sentence break after "Ink".
  #expect(!result.contains("ˈɪŋk."))
}

@Test func testAbbreviations_TitleAndRankEndToEnd() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Capt. Smith met Sen. Jones.")
  #expect(result.contains("kˈæptᵊn"))   // captain
  // "sˈɛnə" is the senator prefix; the medial T allophone (ɾ vs T) can vary
  // by phonological context, but the senator-not-letters part is what matters.
  #expect(result.contains("sˈɛnə"))
  // Neither expanded title should be followed by a period — they're both
  // mid-sentence and would produce unnatural pauses if treated as terminators.
  #expect(!result.contains("kˈæptᵊn."))
  #expect(!result.contains("sˈɛnə."))
}

// At end of input, the original period doubles as the sentence terminator,
// so the expanded form must keep its period to retain final-utterance prosody.
@Test func testAbbreviations_EndOfInputKeepsTerminator() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "She works at Apple Inc.")
  #expect(result.contains("ˈɪŋk"))     // "ink" phoneme appears
  #expect(result.hasSuffix("."))       // trailing period preserved as terminator
}
