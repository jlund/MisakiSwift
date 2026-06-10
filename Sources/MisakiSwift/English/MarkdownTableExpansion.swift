import Foundation

/// Rewrites GitHub-flavored Markdown pipe tables into spoken prose so the TTS
/// engine reads a table as *"Table with 4 rows and 5 columns labeled Name,
/// Age, … Row 1: …"* instead of feeding pipe characters to the g2p fallback
/// as out-of-vocabulary garble and delimiter rows as strings of em-dash
/// pauses.
///
/// Pure String → String with no G2P machinery — like
/// `EmojiExpansion.stripEmoji(_:)`, the app calls it *before* chunking: a
/// multi-line table would otherwise be split row-per-chunk and never reach
/// `phonemize()` intact. The transcript then displays (and highlights) the
/// spoken prose.
///
/// Hand-rolled line-based parser: GFM pipe tables are a line-oriented format
/// (header row + delimiter row + body rows), so a full Markdown dependency
/// would be overkill for the two line classifiers and cell splitter needed.
public enum MarkdownTableExpansion {

  /// Replace every GFM pipe table in `text` with a spoken-prose paragraph,
  /// leaving all other lines untouched (byte-for-byte, including blank lines
  /// and CRLF endings — classifiers strip a trailing `\r` for inspection
  /// only, never from passthrough lines).
  public static func describeTables(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    var out: [String] = []
    var i = 0
    while i < lines.count {
      guard let table = parseTable(in: lines, at: i) else {
        out.append(lines[i])
        i += 1
        continue
      }
      // "End of table." is only worth a listener's time when content follows;
      // as the final content of the input it's dead weight.
      let textFollows = lines[table.nextIndex...].contains {
        !strippingCarriageReturn($0).trimmingCharacters(in: .whitespaces).isEmpty
      }
      out.append(prose(headers: table.headers, rows: table.rows, includeEndMarker: textFollows))
      i = table.nextIndex
    }
    return out.joined(separator: "\n")
  }

  // MARK: - Parsing

  /// A table starts at `index` iff that line is a plausible header (≤3-space
  /// indent, contains an unescaped pipe) and the next line is a delimiter row
  /// whose cell count matches the header's (GFM requires the counts to match,
  /// else the lines are ordinary paragraph text). Body rows run until a blank
  /// or pipe-less line, which is preserved verbatim. Per GFM, a body row's
  /// excess cells are ignored and missing cells are empty.
  private static func parseTable(
    in lines: [String], at index: Int
  ) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
    guard index + 1 < lines.count,
          isCandidateHeader(lines[index]),
          let columnCount = delimiterColumnCount(lines[index + 1]) else { return nil }
    let headers = splitCells(lines[index])
    guard headers.count == columnCount else { return nil }

    var rows: [[String]] = []
    var next = index + 2
    while next < lines.count {
      let line = strippingCarriageReturn(lines[next])
      if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
      if !hasUnescapedPipe(line) { break }
      var cells = splitCells(lines[next])
      if cells.count > columnCount { cells = Array(cells.prefix(columnCount)) }
      while cells.count < columnCount { cells.append("") }
      rows.append(cells)
      next += 1
    }
    return (headers, rows, next)
  }

  /// A header row must contain an unescaped pipe and sit within GFM's
  /// 3-space indent allowance (4+ spaces or a leading tab is a code block).
  private static func isCandidateHeader(_ rawLine: String) -> Bool {
    let line = strippingCarriageReturn(rawLine)
    guard withinIndentAllowance(line) else { return false }
    return hasUnescapedPipe(line)
  }

  /// The number of columns declared by a GFM delimiter row (`| --- |:--:|`),
  /// or `nil` if the line isn't one. Requiring at least one pipe is what
  /// rejects thematic breaks (`---`) and setext-heading underlines.
  static func delimiterColumnCount(_ rawLine: String) -> Int? {
    var line = strippingCarriageReturn(rawLine)
    guard withinIndentAllowance(line) else { return nil }
    line = line.trimmingCharacters(in: .whitespaces)
    guard line.contains("|") else { return nil }
    if line.hasPrefix("|") { line.removeFirst() }
    if line.hasSuffix("|") { line.removeLast() }
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    // A backslash can't appear in a valid delimiter cell, so a raw split is
    // safe here (an escape would just fail the dash check below).
    let cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    for cell in cells {
      var body = Substring(cell)
      if body.hasPrefix(":") { body.removeFirst() }
      if body.hasSuffix(":") { body.removeLast() }
      guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return nil }
    }
    return cells.count
  }

  /// Whether the line contains a pipe that isn't part of a `\|` escape. Uses
  /// the same (and only) escape rule as `splitCells`: a backslash is special
  /// solely when immediately followed by a pipe.
  static func hasUnescapedPipe(_ rawLine: String) -> Bool {
    let line = strippingCarriageReturn(rawLine)
    var index = line.startIndex
    while index < line.endIndex {
      if line[index] == "\\",
         line.index(after: index) < line.endIndex,
         line[line.index(after: index)] == "|" {
        index = line.index(index, offsetBy: 2)
        continue
      }
      if line[index] == "|" { return true }
      index = line.index(after: index)
    }
    return false
  }

  /// Split a row into trimmed cells: one optional outer pipe is dropped from
  /// each end (the *pipe characters*, not post-split empty cells — `|| a |`
  /// keeps its genuinely empty first cell), and `\|` becomes a literal pipe
  /// in the cell content.
  static func splitCells(_ rawLine: String) -> [String] {
    var line = strippingCarriageReturn(rawLine).trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("|") { line.removeFirst() }
    if line.hasSuffix("|"),
       line.index(line.endIndex, offsetBy: -2, limitedBy: line.startIndex).map({ line[$0] != "\\" }) ?? true {
      line.removeLast()
    }
    var cells: [String] = []
    var current = ""
    var index = line.startIndex
    while index < line.endIndex {
      let character = line[index]
      if character == "\\",
         line.index(after: index) < line.endIndex,
         line[line.index(after: index)] == "|" {
        current.append("|")
        index = line.index(index, offsetBy: 2)
        continue
      }
      if character == "|" {
        cells.append(current)
        current = ""
        index = line.index(after: index)
        continue
      }
      current.append(character)
      index = line.index(after: index)
    }
    cells.append(current)
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
  }

  /// GFM treats 4+ leading spaces (or a leading tab) as an indented code
  /// block, so such lines can't open a table.
  private static func withinIndentAllowance(_ line: String) -> Bool {
    var leadingSpaces = 0
    for character in line {
      if character == " " {
        leadingSpaces += 1
        if leadingSpaces > 3 { return false }
      } else if character == "\t" {
        return false
      } else {
        break
      }
    }
    return true
  }

  private static func strippingCarriageReturn(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
  }

  // MARK: - Prose

  /// One paragraph replacing the table's lines: an announcement sentence,
  /// one sentence per data row, and optionally a closing marker. Counts stay
  /// as digits (the existing number path speaks them); commas, colons, and
  /// periods ride the existing punctuation-pause handling.
  static func prose(headers: [String], rows: [[String]], includeEndMarker: Bool) -> String {
    var sentences: [String] = []

    var announcement = "Table with \(rows.count) row\(rows.count == 1 ? "" : "s")"
      + " and \(headers.count) column\(headers.count == 1 ? "" : "s")"
    // Headers that are all empty (after markup cleanup) have nothing to
    // announce; a mix keeps positional alignment by speaking "blank".
    if headers.contains(where: { !cleanedCell($0).isEmpty }) {
      announcement += " labeled " + naturalList(headers.map(spokenCell))
    }
    sentences.append(announcement + ".")

    for (offset, row) in rows.enumerated() {
      sentences.append("Row \(offset + 1): " + row.map(spokenCell).joined(separator: ", ") + ".")
    }
    if includeEndMarker { sentences.append("End of table.") }
    return sentences.joined(separator: " ")
  }

  /// Cell content with emphasis/code markers mapped to spaces — not deleted,
  /// so "3*4" reads as "3 4", never the wrong number "34" — and whitespace
  /// runs collapsed. Underscores stay (snake_case identifiers).
  private static func cleanedCell(_ raw: String) -> String {
    let unmarked = String(raw.map { $0 == "*" || $0 == "`" ? " " : $0 })
    return unmarked
      .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
  }

  /// The spoken form of a cell: its cleaned content, or "blank" when empty
  /// (the VoiceOver convention — silently skipping a cell would shift every
  /// later value's perceived column for the listener).
  private static func spokenCell(_ raw: String) -> String {
    let cleaned = cleanedCell(raw)
    return cleaned.isEmpty ? "blank" : cleaned
  }

  /// "X" / "X and Y" / "X, Y, and Z" — matches the emoji list phrasing.
  private static func naturalList(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return "\(items[0]) and \(items[1])"
    default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
    }
  }
}
