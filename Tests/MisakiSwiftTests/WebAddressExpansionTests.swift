import Testing
import Foundation
@testable import MisakiSwift

// MARK: - Web address expansion (pure String → String; CLI-safe)
//
// Naming is load-bearing: pure tests are prefixed testWebAddress_ so the CLI
// filter `swift test --filter testWebAddress_` runs only the phonemize-free
// tests; the full-pipeline tests use testWebAddressPhonemize_ and need
// Xcode/xcodebuild (CLI swift test crashes on the MLX metallib).

private func natural(_ text: String) -> String {
  WebAddressExpansion.speakAddresses(in: text)
}

private func placeholder(_ text: String) -> String {
  WebAddressExpansion.speakAddresses(in: text, style: .placeholder)
}

// MARK: Scheme URLs

@Test func testWebAddress_SchemeURLWithWWW() async throws {
  #expect(natural("Check out https://www.google.com for details.")
    == "Check out, google dot com, for details.")
}

@Test func testWebAddress_SchemeURLNoWWWWithPath() async throws {
  #expect(natural("https://example.com/about") == "example dot com slash about")
}

@Test func testWebAddress_HTTPSchemeAlsoMatches() async throws {
  #expect(natural("http://example.com works too.") == "example dot com, works too.")
}

@Test func testWebAddress_UserinfoDropped() async throws {
  #expect(natural("https://user:pass@example.com/x") == "example dot com slash X")
}

// MARK: www hosts and bare domains

@Test func testWebAddress_WWWOnly() async throws {
  #expect(natural("Go to www.example.com now.") == "Go to, example dot com, now.")
}

@Test func testWebAddress_WWWDigitLabel() async throws {
  #expect(natural("See www2.example.com today.") == "See, example dot com, today.")
}

@Test func testWebAddress_BareDomainMidSentence() async throws {
  #expect(natural("Search google.com for it.") == "Search, google dot com, for it.")
}

@Test func testWebAddress_BareDomainSentenceEnd() async throws {
  #expect(natural("Try google.com.") == "Try, google dot com.")
}

@Test func testWebAddress_SubdomainKept() async throws {
  #expect(natural("docs.google.com") == "docs dot google dot com")
}

@Test func testWebAddress_AddressOnlyInput() async throws {
  #expect(natural("https://google.com") == "google dot com")
}

@Test func testWebAddress_MultipleAddressesPerSentence() async throws {
  #expect(natural("See a.com and b.org now.") == "See, A dot com, and, B dot org, now.")
}

@Test func testWebAddress_AllCapsFlyerText() async throws {
  #expect(natural("VISIT EXAMPLE.COM TODAY.") == "VISIT, example dot com, TODAY.")
}

// MARK: Trailing punctuation and wrapping

@Test func testWebAddress_TrailingPunctuationVariants() async throws {
  #expect(natural("Visit google.com, then rest.") == "Visit, google dot com, then rest.")
  #expect(natural("Really google.com!") == "Really, google dot com!")
  #expect(natural("Have you tried google.com?") == "Have you tried, google dot com?")
  #expect(natural("See google.com… anyway.") == "See, google dot com… anyway.")
  #expect(natural("It's on https://example.com; check it.") == "It's on, example dot com; check it.")
}

@Test func testWebAddress_ParensAndQuotes() async throws {
  #expect(natural("(see x.com)") == "(see, X dot com)")
  #expect(natural("\"google.com\" is popular.") == "\"google dot com\" is popular.")
}

@Test func testWebAddress_BalancedParensKeptInPath() async throws {
  #expect(natural("(docs: https://en.wikipedia.org/wiki/Chess_(game))")
    == "(docs: E.N dot wikipedia dot org slash wiki slash chess game)")
}

@Test func testWebAddress_LineBoundariesSuppressCommas() async throws {
  #expect(natural("Links:\nhttps://a.com\nDone.") == "Links:\nA dot com\nDone.")
}

// MARK: Label rendering

@Test func testWebAddress_HyphensAndUnderscores() async throws {
  #expect(natural("my-site.com/my_page") == "my site dot com slash my page")
}

@Test func testWebAddress_SpelledTLDs() async throws {
  #expect(natural("example.io") == "example dot I.O")
  #expect(natural("x.ai") == "X dot A.I")
  #expect(natural("visitcanada.ca") == "visitcanada dot C.A")
  #expect(natural("school.edu") == "school dot E.D.U")
  #expect(natural("example.co.uk") == "example dot C.O dot U.K")
  #expect(natural("twitch.tv") == "twitch dot T.V")
}

@Test func testWebAddress_WordTLDs() async throws {
  #expect(natural("example.org") == "example dot org")
  #expect(natural("example.net") == "example dot net")
  #expect(natural("irs.gov") == "I.R.S dot gov")
  #expect(natural("example.app") == "example dot app")
  #expect(natural("example.dev") == "example dot dev")
  #expect(natural("example.info") == "example dot info")
}

@Test func testWebAddress_ConsonantHostsSpelled() async throws {
  #expect(natural("cnn.com") == "C.N.N dot com")
  #expect(natural("x.com") == "X dot com")
  #expect(natural("nyc.gov") == "N.Y.C dot gov")
}

// Three-letter labels defer to the gold dictionaries: known strings read as
// words, unknown ones are initialisms and spell.
@Test func testWebAddress_ThreeLetterLabelsUseDictionary() async throws {
  #expect(natural("fox.com") == "fox dot com")
  #expect(natural("sky.com") == "sky dot com")
  #expect(natural("ibm.com") == "I.B.M dot com")
  #expect(natural("example.com/api/status") == "example dot com slash A.P.I slash status")
}

@Test func testWebAddress_DigitRuns() async throws {
  #expect(natural("route66.com") == "route 66 dot com")
}

@Test func testWebAddress_FileExtensionsInPath() async throws {
  #expect(natural("example.com/report.pdf") == "example dot com slash report dot P.D.F")
  #expect(natural("example.com/docs/index.html")
    == "example dot com slash docs slash index dot H.T.M.L")
}

@Test func testWebAddress_PercentDecoding() async throws {
  #expect(natural("example.com/New%20York") == "example dot com slash new york")
  // Invalid escapes must not crash; the raw segment is spoken instead.
  #expect(natural("example.com/50%ZZoff") == "example dot com slash 50 zzoff")
}

@Test func testWebAddress_UppercaseInput() async throws {
  #expect(natural("WWW.EXAMPLE.COM/PAGE") == "example dot com slash page")
}

// MARK: Queries, fragments, ports, and path budgets

@Test func testWebAddress_QueryAndFragmentDropped() async throws {
  #expect(natural("example.com/search?q=cats") == "example dot com slash search, and more")
  #expect(natural("example.com/page#top") == "example dot com slash page, and more")
  #expect(natural("google.com?q=x") == "google dot com, and more")
}

@Test func testWebAddress_PortAndTrailingSlashDropped() async throws {
  #expect(natural("example.com:8080/status") == "example dot com slash status")
  #expect(natural("example.com/") == "example dot com")
}

@Test func testWebAddress_LongPathsCapped() async throws {
  #expect(natural("tracker.example.com/campaign/a/b/c/d")
    == "tracker dot example dot com slash campaign slash A slash B, and more")
  #expect(natural("example.com/one-two-three-four-five-six/seven-eight-nine-ten-eleven-twelve-thirteen")
    == "example dot com slash one two three four five six, and more")
}

@Test func testWebAddress_UnspeakableSegmentBails() async throws {
  #expect(natural("example.com/download/x7Kq9aZ3")
    == "example dot com slash download, and more")
}

// When a path exceeds the budget, digit-only segments (date scaffolding,
// numeric IDs) are dropped first so the budget reaches the slug — the part a
// listener actually wants.
@Test func testWebAddress_DigitSegmentsDroppedForSlug() async throws {
  #expect(natural("https://www.nytimes.com/2026/07/14/dining/restaurant-review-ambassadors-clubhouse-nyc.html")
    == "nytimes dot com slash dining slash restaurant review ambassadors clubhouse N.Y.C dot H.T.M.L, and more")
  #expect(natural("blog.example.com/2026/07/14/my-first-post")
    == "blog dot example dot com slash my first post, and more")
}

// Digit segments keep their place when the whole path fits the budget.
@Test func testWebAddress_DigitSegmentsKeptWhenTheyFit() async throws {
  #expect(natural("example.com/2026/07/report")
    == "example dot com slash 2026 slash 07 slash report")
}

// MARK: Emails

@Test func testWebAddress_EmailBasic() async throws {
  #expect(natural("Email josh@binaryteaparty.com now.")
    == "Email, josh at binaryteaparty dot com, now.")
}

@Test func testWebAddress_EmailDottedLocal() async throws {
  #expect(natural("first.last@example.org") == "first dot last at example dot org")
}

@Test func testWebAddress_EmailPlusTag() async throws {
  #expect(natural("josh+news@example.com") == "josh plus news at example dot com")
}

@Test func testWebAddress_Mailto() async throws {
  #expect(natural("Write mailto:josh@example.com soon.")
    == "Write, josh at example dot com, soon.")
}

// MARK: Markdown links

@Test func testWebAddress_MarkdownLinkSpokenAsAnchor() async throws {
  #expect(natural("See [Read the study](https://www.nytimes.com/2026/health.html?x=1) when you can.")
    == "See, Read the study, link, when you can.")
}

@Test func testWebAddress_MarkdownBareDomainPayload() async throws {
  #expect(natural("[docs](example.com)") == "docs, link")
}

@Test func testWebAddress_MarkdownEmailPayload() async throws {
  #expect(natural("[mail me](josh@x.com)") == "mail me, link")
}

@Test func testWebAddress_MarkdownAnchorIsAddress() async throws {
  #expect(natural("[x.com](https://x.com)") == "X dot com, link")
}

@Test func testWebAddress_MarkdownPlaceholderCollapses() async throws {
  #expect(placeholder("[x.com](https://x.com)") == "link")
}

// Misaki's own pronunciation-override links ([word](/fˈOnimz/), [word](2),
// [word](#flag#)) must pass through byte-identical for EnglishG2P.preprocess.
@Test func testWebAddress_MarkdownPhonemeOverridePassthrough() async throws {
  for input in [
    "It's [Misaki](/misˈɑki/) speaking.",
    "Stress [word](2) here.",
    "Flagged [nums](#123#) now.",
    "Not a URL payload [ver](v2.0.1) either.",
  ] {
    #expect(natural(input) == input)
    #expect(placeholder(input) == input)
  }
}

// MARK: Non-matches pass through byte-identical

@Test func testWebAddress_NonMatchesUntouched() async throws {
  for input in [
    "Pi is roughly 3.14 today.",
    "Use e.g. the second one.",
    "That is, i.e. this one.",
    "The U.S. team won.",
    "Version v2.0.1 shipped.",
    "Node.js and README.md and script.sh files.",
    "Mr. Smith arrived.",
    "It rose 12.5% by 9.30 a.m. today.",
    "Steps 1.2.3 and 4.5.6 follow.",
    "Ping 192.168.1.1 now.",
    "Ellipsis trails off... nothing here.",
    "google.\ncom split across lines.",
    "Scanned glue google.com.Also stays.",
    "Sentence glue site.In fact stays too.",
  ] {
    #expect(natural(input) == input)
  }
}

@Test func testWebAddress_PlainProseUnchanged() async throws {
  let prose = "No addresses here, just words."
  #expect(natural(prose) == prose)
  #expect(placeholder(prose) == prose)
}

// MARK: Placeholder style

@Test func testWebAddress_PlaceholderStyle() async throws {
  #expect(placeholder("Check https://x.com and josh@y.org or google.com.")
    == "Check, link, and, link, or, link.")
}

// MARK: Idempotence

@Test func testWebAddress_Idempotent() async throws {
  let sample = "Check out https://www.google.com for details. A backup lives at "
    + "docs.example.io and the form is at example.ca. Questions? Email "
    + "josh@binaryteaparty.com. [Read the study](https://www.nytimes.com/2026/07/14/"
    + "health/study.html?smid=url-share) when you can. Full data: "
    + "https://tracker.example.com/campaign/a/b/c/x7Kq9aZ3?utm=1#r"
  let once = natural(sample)
  #expect(natural(once) == once)
  let linkOnce = placeholder(sample)
  #expect(placeholder(linkOnce) == linkOnce)
}

// MARK: - Full-pipeline tests (Xcode/xcodebuild only — MLX metallib crashes
// under CLI `swift test`)

@Test func testWebAddressPhonemize_GoogleDotCom() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "Check out https://www.google.com for details.")
  let (result, _) = englishG2P.phonemize(text: spoken)
  #expect(result.contains("ɡˈuɡᵊl dˈɑt kˈɑm"))
}

// Dotted capitals must ride the M.R.C.S. acronym path: joined letter names,
// no determiner-schwa ("uh") and no stray pauses.
@Test func testWebAddressPhonemize_SpelledTLD() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "The form is at example.ca today.")
  let (result, _) = englishG2P.phonemize(text: spoken)
  #expect(result.contains("ɪɡzˈæmpəl dˈɑt sˌiˈA"))
}

@Test func testWebAddressPhonemize_Email() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "Email josh@example.com now.")
  let (result, _) = englishG2P.phonemize(text: spoken)
  #expect(result.contains("æt ɪɡzˈæmpəl dˈɑt kˈɑm"))
}

// "gov" rides the new gold entry instead of the fallback network.
@Test func testWebAddressPhonemize_GovGoldEntry() async throws {
  let englishG2P = EnglishG2P(british: false)
  let spoken = WebAddressExpansion.speakAddresses(in: "Forms live at irs.gov today.")
  let (result, _) = englishG2P.phonemize(text: spoken)
  #expect(result.contains("dˈɑt ɡˈʌv"))
}

