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
  #expect(result.contains("pˈQndz"))   // "pounds" phoneme
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
