import Testing
import Foundation
@testable import MisakiSwift

// MARK: - Markdown table expansion (pure String → String; CLI-safe)
//
// Naming is load-bearing: pure tests are prefixed testMarkdownTable_ so the
// CLI filter `swift test --filter testMarkdownTable_` runs only the
// phonemize-free tests; the full-pipeline tests use testMarkdownTablePhonemize_
// and need Xcode/xcodebuild (CLI swift test crashes on the MLX metallib).

private let exampleTable = """
| Name       | Age | City          | Occupation       | Salary   |
|------------|-----|---------------|------------------|----------|
| Alice Chen | 29  | San Francisco | Software Engineer | $120,000 |
| Bob Martin | 34  | New York      | Product Manager  | $105,000 |
| Sara Lopez | 27  | Austin        | UX Designer      | $88,000  |
| James Kim  | 41  | Seattle       | Data Scientist   | $135,000 |
"""

private let exampleProse = "Table with 4 rows and 5 columns labeled Name, Age, City, Occupation, and Salary. "
  + "Row 1: Alice Chen, 29, San Francisco, Software Engineer, $120,000. "
  + "Row 2: Bob Martin, 34, New York, Product Manager, $105,000. "
  + "Row 3: Sara Lopez, 27, Austin, UX Designer, $88,000. "
  + "Row 4: James Kim, 41, Seattle, Data Scientist, $135,000."

@Test func testMarkdownTable_ExampleTableExactProse() async throws {
  #expect(MarkdownTableExpansion.describeTables(exampleTable) == exampleProse)
}

// Text without a header+delimiter pair must pass through identically: prose,
// inline pipes, thematic breaks, and setext-heading underlines are not tables.
@Test func testMarkdownTable_NonTableTextUnchanged() async throws {
  for input in [
    "Just some prose.\nWith two lines.",
    "a | b\nplain second line",
    "a | b\n-----",
    "---",
    "Title\n---",
    "either | or, and that's fine",
  ] {
    #expect(MarkdownTableExpansion.describeTables(input) == input)
  }
}

// GFM doesn't require outer pipes. Also pins the singular "1 row" form and
// the two-item "and" join.
@Test func testMarkdownTable_NoOuterPipes() async throws {
  let input = "Name | Age\n--- | ---\nAlice | 29"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 1 row and 2 columns labeled Name and Age. Row 1: Alice, 29.")
}

@Test func testMarkdownTable_AlignmentColons() async throws {
  let plain = "| L | C | R |\n| --- | --- | --- |\n| 1 | 2 | 3 |"
  let aligned = "| L | C | R |\n|:---|:--:|---:|\n| 1 | 2 | 3 |"
  let expected = "Table with 1 row and 3 columns labeled L, C, and R. Row 1: 1, 2, 3."
  #expect(MarkdownTableExpansion.describeTables(plain) == expected)
  #expect(MarkdownTableExpansion.describeTables(aligned) == expected)
}

// Per GFM: excess cells in a body row are ignored, missing cells are empty.
@Test func testMarkdownTable_RaggedRows() async throws {
  let input = "| a | b | c |\n| --- | --- | --- |\n| 1 | 2 | 3 | 4 |\n| 9 |"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 2 rows and 3 columns labeled a, b, and c. Row 1: 1, 2, 3. Row 2: 9, blank, blank.")
}

// \| is a literal pipe inside cell content, not a cell boundary.
@Test func testMarkdownTable_EscapedPipe() async throws {
  let input = "| a \\| b | c |\n| --- | --- |\n| 1 \\| 2 | 3 |"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 1 row and 2 columns labeled a | b and c. Row 1: 1 | 2, 3.")
}

// Empty cells speak as "blank" so later values don't shift columns on the
// listener.
@Test func testMarkdownTable_EmptyCellsSpokenAsBlank() async throws {
  let input = "| a |  | c |\n| --- | --- | --- |\n| 1 |  | 3 |"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 1 row and 3 columns labeled a, blank, and c. Row 1: 1, blank, 3.")
}

// Both tables transform; the prose between them is verbatim; only the table
// with following content gets the "End of table." marker.
@Test func testMarkdownTable_MultipleTablesWithProseBetween() async throws {
  let input = "| A |\n|---|\n| 1 |\n\nBetween.\n\n| B |\n|---|\n| 2 |"
  let expected = "Table with 1 row and 1 column labeled A. Row 1: 1. End of table."
    + "\n\nBetween.\n\n"
    + "Table with 1 row and 1 column labeled B. Row 1: 2."
  #expect(MarkdownTableExpansion.describeTables(input) == expected)
}

@Test func testMarkdownTable_TableAtStartAndAtEnd() async throws {
  let atStart = "| A |\n|---|\n| 1 |\nAfter."
  #expect(MarkdownTableExpansion.describeTables(atStart)
    == "Table with 1 row and 1 column labeled A. Row 1: 1. End of table.\nAfter.")

  let atEnd = "Before.\n| A |\n|---|\n| 1 |"
  #expect(MarkdownTableExpansion.describeTables(atEnd)
    == "Before.\nTable with 1 row and 1 column labeled A. Row 1: 1.")
}

// Header + delimiter with no data rows is still announced.
@Test func testMarkdownTable_ZeroDataRows() async throws {
  #expect(MarkdownTableExpansion.describeTables("| A | B |\n| --- | --- |")
    == "Table with 0 rows and 2 columns labeled A and B.")
}

@Test func testMarkdownTable_SingleColumn() async throws {
  #expect(MarkdownTableExpansion.describeTables("| Name |\n| --- |\n| Alice |")
    == "Table with 1 row and 1 column labeled Name. Row 1: Alice.")
}

// Blank lines around a table survive byte-for-byte.
@Test func testMarkdownTable_SurroundingNewlinesPreserved() async throws {
  let input = "Intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nOutro"
  let expected = "Intro\n\n"
    + "Table with 1 row and 2 columns labeled A and B. Row 1: 1, 2. End of table."
    + "\n\nOutro"
  #expect(MarkdownTableExpansion.describeTables(input) == expected)
}

// Emphasis/code markers map to spaces ("3*4" → "3 4", never "34");
// underscores are left alone.
@Test func testMarkdownTable_MarkupStrippedInCells() async throws {
  let input = "| h1 | h2 | h3 | h4 |\n|---|---|---|---|\n| **Alice** | `code` | 3*4 | snake_case |"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 1 row and 4 columns labeled h1, h2, h3, and h4. Row 1: Alice, code, 3 4, snake_case.")
}

// GFM: header and delimiter cell counts must match, else it's not a table.
@Test func testMarkdownTable_DelimiterCountMismatchNotATable() async throws {
  let input = "| a | b | c |\n| --- | --- |\n| 1 | 2 | 3 |"
  #expect(MarkdownTableExpansion.describeTables(input) == input)
}

// A line without an unescaped pipe ends the table and is preserved verbatim.
@Test func testMarkdownTable_PipelessLineEndsTable() async throws {
  let input = "| A |\n|---|\n| 1 |\nplain text"
  #expect(MarkdownTableExpansion.describeTables(input)
    == "Table with 1 row and 1 column labeled A. Row 1: 1. End of table.\nplain text")
}

// GFM's indent rule: up to 3 leading spaces is a table, 4+ is a code block.
@Test func testMarkdownTable_IndentationRule() async throws {
  let threeSpaces = "   | A |\n   |---|\n   | 1 |"
  #expect(MarkdownTableExpansion.describeTables(threeSpaces)
    == "Table with 1 row and 1 column labeled A. Row 1: 1.")

  let fourSpaces = "    | A |\n    |---|\n    | 1 |"
  #expect(MarkdownTableExpansion.describeTables(fourSpaces) == fourSpaces)
}

// All-blank headers drop the "labeled" clause; a single blank header speaks
// as "blank" to hold its position in the list.
@Test func testMarkdownTable_BlankHeaders() async throws {
  let allBlank = "|  |  |\n| --- | --- |\n| 1 | 2 |"
  #expect(MarkdownTableExpansion.describeTables(allBlank)
    == "Table with 1 row and 2 columns. Row 1: 1, 2.")

  let oneBlank = "|  | Age |\n| --- | --- |\n| 1 | 2 |"
  #expect(MarkdownTableExpansion.describeTables(oneBlank)
    == "Table with 1 row and 2 columns labeled blank and Age. Row 1: 1, 2.")
}

@Test func testMarkdownTable_EmptyInput() async throws {
  #expect(MarkdownTableExpansion.describeTables("") == "")
  #expect(MarkdownTableExpansion.describeTables("   \n ") == "   \n ")
}

// MARK: - Full phonemize path (needs Xcode — CLI swift test crashes on the
// MLX metallib for any phonemize-based test)

// The transformed table must phonemize cleanly: nothing falls through to the
// "❓" unknown marker the way raw pipes garble today.
@Test func testMarkdownTablePhonemize_NoUnknowns() async throws {
  let englishG2P = EnglishG2P(british: false)
  let prose = MarkdownTableExpansion.describeTables(exampleTable)
  let (result, _) = englishG2P.phonemize(text: prose)
  #expect(!result.isEmpty)
  #expect(!result.contains("❓"))
}

// "$120,000" inside a cell rides the existing currency expansion end-to-end.
@Test func testMarkdownTablePhonemize_CurrencyExpansion() async throws {
  let englishG2P = EnglishG2P(british: false)
  let prose = MarkdownTableExpansion.describeTables(exampleTable)
  let (result, _) = englishG2P.phonemize(text: prose)
  #expect(result.contains("dˈɑləɹz"))
}
