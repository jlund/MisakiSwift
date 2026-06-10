import Foundation
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

// The `$` symbol must NOT leak past its own number to a later, unrelated
// number in the same sentence. English number words like "million" /
// "billion" / "three" are tagged .number by NLTagger, so the currency
// chain-break in retokenize() never fires on them; without an explicit
// clear after attach, "$818 million (17%)" produces "...million dollars
// (17 dollars percent)" and "$X million, three times" produces "...million
// dollars, three dollars times".
//
// Helper: count occurrences of `needle` in `haystack`. Most existing tests
// use plain `contains(...)`; these regressions need a count assertion to
// distinguish "appears once on the legitimate amount" from "leaks onto a
// second number".
private func count(_ needle: String, in haystack: String) -> Int {
  haystack.components(separatedBy: needle).count - 1
}

@Test func testCurrency_DoesNotLeakAcrossMillionAndParens() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It made $818 million (17%) from AI.")
  #expect(result.contains("pəɹsˈɛnt"))         // "percent" still pronounced
  #expect(count("dˈɑləɹz", in: result) == 1)   // "dollars" attaches once, not to "17"
}

@Test func testCurrency_DoesNotLeakAcrossCommaToNumberWord() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It spent $7,723 million, three times as much as before.")
  #expect(count("dˈɑləɹz", in: result) == 1)   // attaches once on "million", not on "three"
}

@Test func testCurrency_FullReportedSentence() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(
    text: "It made $818 million (17%) from AI, and had capital expenditures of of $7,723 million, three times as much capex as before."
  )
  #expect(count("dˈɑləɹz", in: result) == 2)   // exactly one per `$X million` group
  #expect(result.contains("pəɹsˈɛnt"))
}

@Test func testCurrency_SimpleNoLeakAcrossParens() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It costs $5 (10% off).")
  #expect(count("dˈɑləɹz", in: result) == 1)   // not "ten dollars percent"
  #expect(result.contains("pəɹsˈɛnt"))
}

// Regression guard: the chain-end clear must not break the existing
// decimal-currency path. "$5.72" comes back from NLTagger as one
// .otherWord token, so the attach + clear happens exactly once and
// both "dollars" and "cents" still come through.
@Test func testCurrency_DecimalStillProducesDollarsAndCents() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It cost $5.72 yesterday.")
  #expect(result.contains("dˈɑləɹz"))
  #expect(result.contains("sˈɛnts"))
}

// Decimal numbers must be parsed via Decimal(string:), not Double(),
// to avoid binary float artifacts. "28.81" via Double becomes
// 28.80999999999999488, which would be spoken digit-by-digit as a long
// run of nines.
@Test func testDecimal_PercentageDoesNotRoundTripThroughDouble() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The score was 28.81%.")
  #expect(result.contains("twˈɛnti"))  // "twenty"
  #expect(result.contains("ˈAt"))      // "eight"
  #expect(result.contains("pˈYnt"))    // "point"
  #expect(result.contains("wˈʌn"))     // "one"
  #expect(result.contains("pəɹsˈɛnt")) // "percent"
  #expect(!result.contains("nˈIn"))    // "nine" must not appear
}

// Monetary magnitude shorthand ("$70bn", "£230mn", "$50k", etc.) gets
// rewritten at preprocessing time to plain words. Without this rewrite the
// whole token slips into the fallback path and the audio loses the number
// and the currency, leaving just a letter spelling of the suffix.
@Test func testMonetaryAbbreviation_BillionDollars() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The deficit grew to $70bn last year.")
  #expect(result.contains("sˈɛvənti")) // "seventy"
  #expect(result.contains("bˈɪljən"))  // "billion"
  #expect(result.contains("dˈɑləɹz"))  // "dollars"
}

@Test func testMonetaryAbbreviation_MillionDollars() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The fund raised $230mn this quarter.")
  #expect(result.contains("hˈʌndɹəd"))  // "hundred"
  #expect(result.contains("θˈɜɹɾi"))    // "thirty"
  #expect(result.contains("mˈɪljᵊn"))   // "million"
  #expect(result.contains("dˈɑləɹz"))   // "dollars"
}

@Test func testMonetaryAbbreviation_ThousandDollars() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "It costs $50k to get started.")
  #expect(result.contains("fˈɪfti"))   // "fifty"
  #expect(result.contains("θˈWzᵊnd"))  // "thousand"
  #expect(result.contains("dˈɑləɹz"))  // "dollars"
}

@Test func testMonetaryAbbreviation_TrillionPounds() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "The market cap is £2tn now.")
  #expect(result.contains("tɹˈɪljən"))  // "trillion"
  #expect(result.contains("pˈWndz"))    // "pounds"
}

// Single-letter suffixes ("$5b", "$5m", "$5t") must also expand — they're
// common in US business writing.
@Test func testMonetaryAbbreviation_SingleLetterSuffix() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (resultB, _) = englishG2P.phonemize(text: "Profit was $5b.")
  #expect(resultB.contains("bˈɪljən"))
  #expect(resultB.contains("dˈɑləɹz"))

  let (resultM, _) = englishG2P.phonemize(text: "Profit was $5m.")
  #expect(resultM.contains("mˈɪljᵊn"))
  #expect(resultM.contains("dˈɑləɹz"))
}

// FT/Economist style "$70 bn" with a space between number and suffix must
// also expand.
@Test func testMonetaryAbbreviation_OptionalSpaceBeforeSuffix() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "The deficit grew to $70 bn last year.")
  #expect(result.contains("sˈɛvənti"))
  #expect(result.contains("bˈɪljən"))
  #expect(result.contains("dˈɑləɹz"))
}

// Plain-text "5m" with no currency prefix must NOT be rewritten (it
// commonly means "5 meters"), and an unsuffixed "$5" must continue to flow
// through the regular currency-retokenization path unchanged.
@Test func testMonetaryAbbreviation_NotConfusedByPlainText() async throws {
  let englishG2P = EnglishG2P(british: false)

  let bare = EnglishG2P.applyAllReplacements(to: "We need 5m of cable.")
  #expect(bare.substitutions.isEmpty)
  #expect(bare.text == "We need 5m of cable.")

  let (currencyOnly, _) = englishG2P.phonemize(text: "It costs $5 only.")
  #expect(currencyOnly.contains("fˈIv"))    // "five"
  #expect(currencyOnly.contains("dˈɑləɹz")) // "dollars" (existing path)
}

// Unit-level checks on the substitution metadata mirror the temperature
// rewrite tests above — the rewrite must capture the full "$70bn" surface
// form, produce exactly three lookup words, and lowercase the suffix so
// "$70BN" maps the same way.
@Test func testMonetaryAbbreviation_SubstitutionMetadata() async throws {
  let billion = EnglishG2P.applyAllReplacements(to: "Up $70bn this year.")
  #expect(billion.substitutions.count == 1)
  #expect(billion.substitutions[0].originalText == "$70bn")
  #expect(billion.substitutions[0].lookupWords == ["70", "billion", "dollars"])

  let mixedCase = EnglishG2P.applyAllReplacements(to: "Up $70BN this year.")
  #expect(mixedCase.substitutions.count == 1)
  #expect(mixedCase.substitutions[0].originalText == "$70BN")
  #expect(mixedCase.substitutions[0].lookupWords == ["70", "billion", "dollars"])

  let pounds = EnglishG2P.applyAllReplacements(to: "Market cap of £2tn.")
  #expect(pounds.substitutions.count == 1)
  #expect(pounds.substitutions[0].originalText == "£2tn")
  #expect(pounds.substitutions[0].lookupWords == ["2", "trillion", "pounds"])

  let spaced = EnglishG2P.applyAllReplacements(to: "Up $70 bn this year.")
  #expect(spaced.substitutions.count == 1)
  #expect(spaced.substitutions[0].originalText == "$70 bn")
  #expect(spaced.substitutions[0].lookupWords == ["70", "billion", "dollars"])
}

// The original surface "$70bn" must end up on a single token, and the
// expansion words must NOT leak into any token's display text. Mirrors
// testTemperatures_TokenSurfaceTextPreserved.
@Test func testMonetaryAbbreviation_TokenSurfaceTextPreserved() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "The deficit grew to $70bn last year.")

  #expect(tokens.contains(where: { $0.text == "$70bn" }))
  #expect(!tokens.contains(where: { $0.text == "billion" }))
  #expect(!tokens.contains(where: { $0.text == "dollars" }))

  let surfaceToken = tokens.first { $0.text == "$70bn" }
  #expect(surfaceToken?.`_`.alias == "70")
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "billion" }))
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "dollars" }))
}

// Reconstruct the chyron string by concatenating `text + whitespace` over
// the returned tokens — it must equal the user's original input verbatim.
@Test func testMonetaryAbbreviation_ChyronConcatenation() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "The deficit grew to $70bn last year.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "The deficit grew to $70bn last year.")
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

// Surface-text preservation for temperatures: same problem the abbreviation
// case had, but 1:N — "110°F" expands to three lookup tokens (110, degrees,
// Fahrenheit). The first covered token must keep "110°F" as its surface text
// so the chyron and the underline-highlighter still see the original input,
// while phoneme generation uses each lookup word in turn.
@Test func testTemperatures_TrackedSubstitutions() async throws {
  let result = EnglishG2P.applyTemperatureReplacements(to: "It was 110°F today.")
  #expect(result.text == "It was 110 degrees Fahrenheit today.")
  #expect(result.substitutions.count == 1)
  #expect(result.substitutions[0].originalText == "110°F")
  #expect(result.substitutions[0].lookupWords == ["110", "degrees", "Fahrenheit"])
  let modifiedSlice = (result.text as NSString).substring(with: result.substitutions[0].modifiedNSRange)
  #expect(modifiedSlice == "110 degrees Fahrenheit")

  // Singular form keeps "degree" not "degrees".
  let singular = EnglishG2P.applyTemperatureReplacements(to: "It dropped to 1°F overnight.")
  #expect(singular.substitutions.count == 1)
  #expect(singular.substitutions[0].originalText == "1°F")
  #expect(singular.substitutions[0].lookupWords == ["1", "degree", "Fahrenheit"])

  // Decimal numbers like "98.6°F" must be captured in their entirety, not
  // just the trailing digit. The widened regex is what makes this work.
  let decimal = EnglishG2P.applyTemperatureReplacements(to: "Body temperature is 98.6°F.")
  #expect(decimal.substitutions.count == 1)
  #expect(decimal.substitutions[0].originalText == "98.6°F")
  #expect(decimal.substitutions[0].lookupWords == ["98.6", "degrees", "Fahrenheit"])

  // Celsius and bare-degree variants get the same treatment.
  let celsius = EnglishG2P.applyTemperatureReplacements(to: "Water boils at 100°C.")
  #expect(celsius.substitutions.count == 1)
  #expect(celsius.substitutions[0].originalText == "100°C")
  #expect(celsius.substitutions[0].lookupWords == ["100", "degrees", "Celsius"])

  let bare = EnglishG2P.applyTemperatureReplacements(to: "The angle is 45° from vertical.")
  #expect(bare.substitutions.count == 1)
  #expect(bare.substitutions[0].originalText == "45°")
  #expect(bare.substitutions[0].lookupWords == ["45", "degrees"])
}

@Test func testTemperatures_TokenSurfaceTextPreserved() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "The temperature was 110°F today.")

  // The original surface "110°F" must be present as a token text. The
  // expansion words must NOT leak into any token text.
  #expect(tokens.contains(where: { $0.text == "110°F" }))
  #expect(!tokens.contains(where: { $0.text == "degrees" }))
  #expect(!tokens.contains(where: { $0.text == "Fahrenheit" }))

  // Phoneme lookup still happens via aliases — the surface-bearing token
  // looks up "110", and there are display-suppressed tokens for "degrees"
  // and "Fahrenheit".
  let surfaceToken = tokens.first { $0.text == "110°F" }
  #expect(surfaceToken?.`_`.alias == "110")
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "degrees" }))
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "Fahrenheit" }))
}

// Reconstruct the chyron string by concatenating `text + whitespace` over
// the returned tokens — it must equal the user's original input verbatim.
// This is the actual signal the kokoro app's chyron uses (per the agent
// audit of TextGoesHearModel.updateHighlightingForTime).
@Test func testTemperatures_ChyronConcatenationFahrenheit() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "It was 110°F today.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "It was 110°F today.")
}

@Test func testTemperatures_ChyronConcatenationCelsius() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Water boils at 100°C.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "Water boils at 100°C.")
}

@Test func testTemperatures_ChyronConcatenationBareDegree() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "The angle is 45° from vertical.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "The angle is 45° from vertical.")
}

@Test func testTemperatures_ChyronConcatenationSingular() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "It dropped to 1°F overnight.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "It dropped to 1°F overnight.")
}

// Combined input: an abbreviation and a temperature in the same sentence
// must both round-trip through the chyron concatenation. This is the case
// that motivated the unified single-pass `applyAllReplacements` — a chained
// approach corrupts substitution positions when one rewrite shifts text the
// other one already recorded a position against.
@Test func testTemperatures_ChyronWithAbbreviation() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Capt. Smith said it was 110°F.")
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == "Capt. Smith said it was 110°F.")
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

// The substitution-tracking helper underpins surface-text preservation.
// It rewrites the text and records each substitution so the post-tokenize
// step can map expanded tokens back to the original abbreviations.
@Test func testAbbreviations_TrackedSubstitutions() async throws {
  // Mid-sentence: "Jr." → "Junior". The dropped period has no separate token
  // to live in, so it folds into the substitution's originalText to keep
  // chyron rendering and highlight ranges accurate.
  let mid = EnglishG2P.applyAbbreviationReplacements(to: "Harold Jones Jr. went home.")
  #expect(mid.text == "Harold Jones Junior went home.")
  #expect(mid.substitutions.count == 1)
  #expect(mid.substitutions[0].originalText == "Jr.")  // includes the dropped period
  #expect(mid.substitutions[0].lookupWords == ["Junior"])
  let modifiedSlice = (mid.text as NSString).substring(with: mid.substitutions[0].modifiedNSRange)
  #expect(modifiedSlice == "Junior")

  // End-of-input: "Inc." → "Ink." — the period is preserved as its own token
  // in the modified text, so the substitution covers just "Inc" (letters
  // only). If we included the period here the chyron would render "Apple
  // Inc.." (double period) when concatenating the period token's text.
  let eoi = EnglishG2P.applyAbbreviationReplacements(to: "She works at Apple Inc.")
  #expect(eoi.text == "She works at Apple Ink.")
  #expect(eoi.substitutions.count == 1)
  #expect(eoi.substitutions[0].originalText == "Inc")  // letters only
  #expect(eoi.substitutions[0].lookupWords == ["Ink"])
  let eoiSlice = (eoi.text as NSString).substring(with: eoi.substitutions[0].modifiedNSRange)
  #expect(eoiSlice == "Ink")

  // Multiple abbreviations in one text — each is tracked independently.
  let multi = EnglishG2P.applyAbbreviationReplacements(to: "Capt. Smith met Sen. Jones.")
  #expect(multi.text == "Captain Smith met Senator Jones.")
  #expect(multi.substitutions.count == 2)
  #expect(multi.substitutions[0].originalText == "Capt.")
  #expect(multi.substitutions[0].lookupWords == ["Captain"])
  #expect(multi.substitutions[1].originalText == "Sen.")
  #expect(multi.substitutions[1].lookupWords == ["Senator"])
}

// After phonemize() runs, the returned tokens for an abbreviated word must
// expose the *original* surface text in `token.text` (so the kokoro app's
// chyron and underline-highlighter can find them via substring search in
// the original input) while carrying the expansion in `_.alias` for lexicon
// lookup. Without this, the chyron would display "Junior" instead of "Jr."
// and `text.range(of: token.text)` would fail to find "Junior" in the input.
@Test func testAbbreviations_TokenSurfaceTextPreserved() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Harold Jones Jr. went to the store.")

  // Mid-sentence: token surface includes the original period so the chyron
  // and highlight underline cover "Jr." in the original input, not just "Jr".
  let jrToken = tokens.first { $0.text == "Jr." }
  #expect(jrToken != nil, "expected a token whose text is the original 'Jr.', not the expansion")
  #expect(jrToken?.`_`.alias == "Junior", "the token's alias must be the expansion so the lexicon looks up 'Junior'")

  // The expanded form must NOT appear as a token's surface text.
  #expect(!tokens.contains(where: { $0.text == "Junior" }))
}

@Test func testAbbreviations_TokenSurfaceTextPreservedForCompany() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Apple Inc. is a valuable company.")

  let incToken = tokens.first { $0.text == "Inc." }
  #expect(incToken != nil)
  #expect(incToken?.`_`.alias == "Ink")
  #expect(!tokens.contains(where: { $0.text == "Ink" }))
}

@Test func testAbbreviations_TokenSurfaceTextPreservedForMultiple() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Capt. Smith met Sen. Jones.")

  let captToken = tokens.first { $0.text == "Capt." }
  let senToken = tokens.first { $0.text == "Sen." }
  #expect(captToken != nil)
  #expect(senToken != nil)
  #expect(captToken?.`_`.alias == "Captain")
  #expect(senToken?.`_`.alias == "Senator")
  #expect(!tokens.contains(where: { $0.text == "Captain" }))
  #expect(!tokens.contains(where: { $0.text == "Senator" }))
}

// End-of-input case: the substitution covers only the abbreviation letters
// because the trailing period stays as its own token in the modified text.
// So the "Inc" token gets text="Inc" (no period) and a separate "." token
// follows, and concatenating the two yields "Inc." for chyron rendering.
@Test func testAbbreviations_TokenSurfaceTextPreservedAtEndOfInput() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "She works at Apple Inc.")

  let incToken = tokens.first { $0.text == "Inc" }
  #expect(incToken != nil, "expected a token whose text is the original letters 'Inc'")
  #expect(incToken?.`_`.alias == "Ink")

  // A separate sentence-terminator period token must follow so prosody and
  // chyron rendering both stay correct.
  if let incIdx = tokens.firstIndex(where: { $0.text == "Inc" }), incIdx + 1 < tokens.count {
    #expect(tokens[incIdx + 1].text == ".")
  } else {
    Issue.record("expected a '.' token immediately after the 'Inc' token")
  }
}

// Place-name pronunciations: "Los" and "Angeles" each fall back to BART/letter
// spelling when absent from the gold dictionary, producing "Lows Angels".
// Adding gold entries short-circuits the fallback and yields the canonical
// /lɔs ˈændʒələs/ pronunciation.
@Test func testPlaceName_LosAngeles_American() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, _) = englishG2P.phonemize(text: "Los Angeles California")
  #expect(result.contains("lˈɔs"))
  #expect(result.contains("ˈænʤələs"))
  #expect(result.contains("kˌæləfˈɔɹnjə"))
}

@Test func testPlaceName_LosAngeles_British() async throws {
  let englishG2P = EnglishG2P(british: true)
  let (result, _) = englishG2P.phonemize(text: "Los Angeles California")
  #expect(result.contains("lˈɒs"))
  #expect(result.contains("ˈanʤɪləs"))
}

// MARK: - Emoji expansion

// Emoji are expanded into their spoken CLDR names ("sun emoji", "party popper
// emoji") before tokenization, with the original glyph preserved on a single
// token. Mirrors the temperature/monetary substitution-metadata tests.
@Test func testEmoji_SubstitutionMetadata() async throws {
  let sun = EnglishG2P.applyAllReplacements(to: "☀️ Summer")
  #expect(sun.substitutions.count == 1)
  #expect(sun.substitutions[0].originalText == "☀️")
  #expect(sun.substitutions[0].lookupWords == ["sun", "emoji"])
  #expect(sun.substitutions[0].isEmojiRun)
  #expect(sun.substitutions[0].pauseAfterWordIndices.isEmpty)   // single group → no interior pauses

  let party = EnglishG2P.applyAllReplacements(to: "party 🎉")
  #expect(party.substitutions.count == 1)
  #expect(party.substitutions[0].originalText == "🎉")
  #expect(party.substitutions[0].lookupWords == ["party", "popper", "emoji"])

  let flag = EnglishG2P.applyAllReplacements(to: "🇺🇸")
  #expect(flag.substitutions[0].originalText == "🇺🇸")
  #expect(flag.substitutions[0].lookupWords == ["flag", "United", "States", "emoji"])

  let skin = EnglishG2P.applyAllReplacements(to: "👍🏽")
  #expect(skin.substitutions[0].originalText == "👍🏽")
  #expect(skin.substitutions[0].lookupWords == ["thumbs", "up", "medium", "skin", "tone", "emoji"])

  let family = EnglishG2P.applyAllReplacements(to: "👨‍👩‍👧")
  #expect(family.substitutions[0].originalText == "👨‍👩‍👧")
  #expect(family.substitutions[0].lookupWords == ["family", "man", "woman", "girl", "emoji"])
}

// Repeated identical emoji collapse to a spoken count: "❤️❤️❤️" → "3 red heart
// emoji" (the "3" becomes "three" via the existing number path).
@Test func testEmoji_RepeatCollapse() async throws {
  let hearts = EnglishG2P.applyAllReplacements(to: "❤️❤️❤️")
  #expect(hearts.substitutions.count == 1)
  #expect(hearts.substitutions[0].originalText == "❤️❤️❤️")
  #expect(hearts.substitutions[0].lookupWords == ["3", "red", "heart", "emoji"])
  #expect(hearts.substitutions[0].pauseAfterWordIndices.isEmpty)
}

// A bare ❤ (no variation selector) resolves to the same name as ❤️.
@Test func testEmoji_QualifiedAndUnqualifiedResolveSame() async throws {
  let qualified = EnglishG2P.applyAllReplacements(to: "❤️")
  let unqualified = EnglishG2P.applyAllReplacements(to: "❤")
  #expect(qualified.substitutions[0].lookupWords == ["red", "heart", "emoji"])
  #expect(unqualified.substitutions[0].lookupWords == ["red", "heart", "emoji"])
}

// Adjacent (no-space) different emoji form ONE run/substitution, read as a
// natural list: "sun, and party popper emoji" — single trailing "emoji", "and"
// before the final name, pause boundary recorded after each non-final group.
@Test func testEmoji_AdjacentRunIsSingleSubstitution() async throws {
  let run = EnglishG2P.applyAllReplacements(to: "☀️🎉")
  #expect(run.substitutions.count == 1)
  #expect(run.substitutions[0].originalText == "☀️🎉")
  #expect(run.substitutions[0].lookupWords == ["sun", "and", "party", "popper", "emoji"])
  #expect(run.substitutions[0].pauseAfterWordIndices == [0])   // pause after "sun"
}

// The original emoji glyph must end up on a single token; the spoken words must
// NOT leak into any token's display text. Mirrors the monetary surface test.
@Test func testEmoji_TokenSurfaceTextPreserved() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (_, tokens) = englishG2P.phonemize(text: "Hello 🎉 world")

  #expect(tokens.contains(where: { $0.text == "🎉" }))
  #expect(!tokens.contains(where: { $0.text == "party" }))
  #expect(!tokens.contains(where: { $0.text == "popper" }))

  let surfaceToken = tokens.first { $0.text == "🎉" }
  #expect(surfaceToken?.`_`.alias == "party")
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "popper" }))
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "emoji" }))
}

// Reconstruct the chyron by concatenating text + whitespace over the returned
// tokens — it must equal the user's original input verbatim, emoji and all (the
// injected pause tokens are invisible).
@Test func testEmoji_ChyronConcatenation() async throws {
  let englishG2P = EnglishG2P(british: false)
  let input = "☀️ Summer is here, and it's time to celebrate 🎉"
  let (_, tokens) = englishG2P.phonemize(text: input)
  let chyron = tokens.map { $0.text + $0.whitespace }.joined()
  #expect(chyron == input)
}

// A small pause is injected around each emoji run as an invisible token
// (text="" but phonemes=","), so the pause reaches the phoneme stream without
// polluting the chyron.
@Test func testEmoji_PauseTokensInjectedButInvisible() async throws {
  let englishG2P = EnglishG2P(british: false)
  let (result, tokens) = englishG2P.phonemize(text: "Hi 🎉 bye")

  let pauses = tokens.filter { $0.text.isEmpty && $0.phonemes == "," }
  #expect(pauses.count >= 2)   // one before, one after the run
  #expect(tokens.map { $0.text + $0.whitespace }.joined() == "Hi 🎉 bye")
  #expect(result.contains(","))   // the input has no other punctuation
}

// stripEmoji removes emoji and tidies the leftover whitespace; used by the app
// when "Pronounce Emoji Characters" is off.
@Test func testEmoji_StripEmoji() async throws {
  #expect(EmojiExpansion.stripEmoji("☀️ Summer 🎉") == "Summer")
  #expect(EmojiExpansion.stripEmoji("a☀️b") == "ab")
  #expect(EmojiExpansion.stripEmoji("no emoji here") == "no emoji here")
  #expect(EmojiExpansion.stripEmoji("❤️❤️❤️") == "")
}

// An emoji written directly against a word (no space, e.g. "sun☀️") must not
// merge with it during tokenization. The expansion is space-padded on the
// glued side so NLTagger keeps the words distinct; the substitution metadata
// is unchanged and the pad flags record which side(s) were padded.
@Test func testEmoji_GluedToAdjacentWord() async throws {
  let trailing = EnglishG2P.applyAllReplacements(to: "the sun☀️")
  #expect(trailing.substitutions.count == 1)
  #expect(trailing.substitutions[0].originalText == "☀️")
  #expect(trailing.substitutions[0].lookupWords == ["sun", "emoji"])
  #expect(trailing.substitutions[0].padLeft)
  #expect(!trailing.substitutions[0].padRight)
  #expect(trailing.text == "the sun sun emoji")

  let leading = EnglishG2P.applyAllReplacements(to: "☀️sun")
  #expect(!leading.substitutions[0].padLeft)
  #expect(leading.substitutions[0].padRight)
  #expect(leading.text == "sun emoji sun")

  let surrounded = EnglishG2P.applyAllReplacements(to: "a☀️b")
  #expect(surrounded.substitutions[0].padLeft)
  #expect(surrounded.substitutions[0].padRight)
  #expect(surrounded.text == "a sun emoji b")

  // Spaced input is left alone (no padding).
  let spaced = EnglishG2P.applyAllReplacements(to: "the sun ☀️ rises")
  #expect(!spaced.substitutions[0].padLeft)
  #expect(!spaced.substitutions[0].padRight)
}

// Regression for the on-device crash: a glued emoji must phonemize without
// tripping the covered-token assertion, and the chyron must stay verbatim
// (the seam pad is cleared). Exercises the full phonemize path (needs Xcode).
@Test func testEmoji_GluedChyronConcatenation() async throws {
  let englishG2P = EnglishG2P(british: false)
  let input = "This is the sun☀️"
  let (_, tokens) = englishG2P.phonemize(text: input)
  #expect(tokens.map { $0.text + $0.whitespace }.joined() == input)
}

// Identical emoji separated only by spaces group exactly like an adjacent run:
// "❤️ ❤️ ❤️" → one substitution, "three red heart emoji".
@Test func testEmoji_SpaceMergedIdenticalRun() async throws {
  let hearts = EnglishG2P.applyAllReplacements(to: "❤️ ❤️ ❤️")
  #expect(hearts.substitutions.count == 1)
  #expect(hearts.substitutions[0].originalText == "❤️ ❤️ ❤️")
  #expect(hearts.substitutions[0].lookupWords == ["3", "red", "heart", "emoji"])
  #expect(hearts.substitutions[0].pauseAfterWordIndices.isEmpty)
  #expect(hearts.text == "3 red heart emoji")
}

// Distinct emoji separated by spaces merge into the same natural-list run as
// their adjacent counterpart — spacing in the input must not change the audio.
@Test func testEmoji_SpaceMergedDistinctRun() async throws {
  let spaced = EnglishG2P.applyAllReplacements(to: "🤣 🎉 🤗")
  let adjacent = EnglishG2P.applyAllReplacements(to: "🤣🎉🤗")
  #expect(spaced.substitutions.count == 1)
  #expect(spaced.substitutions[0].originalText == "🤣 🎉 🤗")
  #expect(spaced.substitutions[0].lookupWords == [
    "rolling", "on", "the", "floor", "laughing",
    "party", "popper",
    "and", "smiling", "face", "with", "open", "hands",
    "emoji",
  ])
  // Pause after "laughing" and after "popper" (just before the "and").
  #expect(spaced.substitutions[0].pauseAfterWordIndices == [4, 6])
  #expect(spaced.substitutions[0].lookupWords == adjacent.substitutions[0].lookupWords)
  #expect(spaced.substitutions[0].pauseAfterWordIndices == adjacent.substitutions[0].pauseAfterWordIndices)
}

// A repeated-emoji count composes with the list phrasing: the counted group is
// one list item ("two red heart, and party popper emoji").
@Test func testEmoji_CountComposesWithList() async throws {
  for input in ["❤️❤️🎉", "❤️ ❤️ 🎉"] {
    let run = EnglishG2P.applyAllReplacements(to: input)
    #expect(run.substitutions.count == 1)
    #expect(run.substitutions[0].lookupWords == ["2", "red", "heart", "and", "party", "popper", "emoji"])
    #expect(run.substitutions[0].pauseAfterWordIndices == [2])   // pause after "heart"
  }
}

// Newlines break a run — emoji on separate lines are separate thoughts and
// must not collapse into one counted phrase.
@Test func testEmoji_NewlineDoesNotMerge() async throws {
  for input in ["❤️\n❤️", "❤️ \n ❤️"] {
    let hearts = EnglishG2P.applyAllReplacements(to: input)
    #expect(hearts.substitutions.count == 2)
    #expect(hearts.substitutions[0].lookupWords == ["red", "heart", "emoji"])
    #expect(hearts.substitutions[1].lookupWords == ["red", "heart", "emoji"])
  }
}

// Any inline-whitespace gap merges: multiple spaces, tabs, NBSP.
@Test func testEmoji_WhitespaceVariantsMerge() async throws {
  for input in ["❤️  ❤️", "❤️\t❤️", "❤️\u{00A0}❤️"] {
    let hearts = EnglishG2P.applyAllReplacements(to: input)
    #expect(hearts.substitutions.count == 1)
    #expect(hearts.substitutions[0].originalText == input)
    #expect(hearts.substitutions[0].lookupWords == ["2", "red", "heart", "emoji"])
  }
}

// The gap lookahead only absorbs whitespace when another emoji follows — the
// run's range must end at the last glyph, leaving surrounding spaces alone.
@Test func testEmoji_TrailingGapNotAbsorbed() async throws {
  let run = EnglishG2P.applyAllReplacements(to: "a ❤️ ❤️ b")
  #expect(run.substitutions.count == 1)
  #expect(run.substitutions[0].originalText == "❤️ ❤️")
  #expect(!run.substitutions[0].padLeft)
  #expect(!run.substitutions[0].padRight)
}

// A space-merged run glued to neighbouring words pads both seams, like the
// single-emoji glued case.
@Test func testEmoji_GluedAndSpacedCombo() async throws {
  let run = EnglishG2P.applyAllReplacements(to: "sun☀️ ☀️rise")
  #expect(run.substitutions.count == 1)
  #expect(run.substitutions[0].originalText == "☀️ ☀️")
  #expect(run.substitutions[0].lookupWords == ["2", "sun", "emoji"])
  #expect(run.substitutions[0].padLeft)
  #expect(run.substitutions[0].padRight)
  #expect(run.text == "sun 2 sun emoji rise")
}

// A space-merged run round-trips through the full phonemize path: the whole
// run (interior space included) lands on one token and the chyron stays
// verbatim. Exercises the full phonemize path (needs Xcode).
@Test func testEmoji_SpacedRunChyron() async throws {
  let englishG2P = EnglishG2P(british: false)
  let input = "a ❤️ ❤️ b"
  let (_, tokens) = englishG2P.phonemize(text: input)
  #expect(tokens.map { $0.text + $0.whitespace }.joined() == input)
  #expect(tokens.contains(where: { $0.text == "❤️ ❤️" }))
}

// A three-group run gets pauses at every boundary — before the run, after each
// non-final group, and after the run (4 total; the input has no other
// punctuation) — and the "and" flows through the alias path. Exercises the
// full phonemize path (needs Xcode).
@Test func testEmoji_InteriorPausesAndAnd() async throws {
  let englishG2P = EnglishG2P(british: false)
  let input = "Hi 🤣 🎉 🤗 bye"
  let (_, tokens) = englishG2P.phonemize(text: input)

  let pauses = tokens.filter { $0.text.isEmpty && $0.phonemes == "," }
  #expect(pauses.count == 4)
  #expect(tokens.map { $0.text + $0.whitespace }.joined() == input)
  #expect(tokens.contains(where: { $0.text == "" && $0.`_`.alias == "and" }))
}

// Glued + space-merged combined must still reconstruct the chyron verbatim
// through phonemize. Exercises the full phonemize path (needs Xcode).
@Test func testEmoji_GluedSpacedChyron() async throws {
  let englishG2P = EnglishG2P(british: false)
  let input = "sun☀️ ☀️rise"
  let (_, tokens) = englishG2P.phonemize(text: input)
  #expect(tokens.map { $0.text + $0.whitespace }.joined() == input)
}
