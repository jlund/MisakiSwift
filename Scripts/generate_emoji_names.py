#!/usr/bin/env python3
"""Generate ``Resources/emoji_names.json`` for MisakiSwift's emoji expansion.

The app reads each emoji's spoken English name from this bundled table so the
TTS engine can say "sun emoji" / "red heart emoji" instead of garbling the
glyph. The data is derived from Unicode's published files:

  * RGI emoji set ............ Unicode ``emoji-test.txt`` (UTS #51)
  * Spoken short names ....... CLDR ``annotations`` + ``annotationsDerived``
                               ``type="tts"`` (the same names VoiceOver speaks),
                               with the emoji-test name as a fallback.

Both are distributed by Unicode under the Unicode License v3 (SPDX:
Unicode-3.0), which permits redistribution in a commercial app provided the
copyright/permission notice ships in our documentation. The app surfaces that
notice in its "Open Source Licenses" screen.

This is a MANUAL, infrequent step — run it only when bumping the pinned Unicode
/ CLDR versions below. It needs network access.

    python3 Scripts/generate_emoji_names.py

Design notes for the consuming Swift code (EmojiExpansion.swift):
  * Keys are the emoji grapheme cluster with U+FE0F (variation selector-16)
    removed, so both "❤" and "❤️" resolve to the same entry. The runtime must
    strip U+FE0F from input clusters before lookup.
  * Values are pre-normalized to plain space-separated alphanumeric words (no
    ":", ",", "-", or "'"), because the g2p tokenizer (NLTagger) splits on
    punctuation/hyphens — keeping names punctuation-free makes the per-word
    token count predictable so surface-substitution restoration stays aligned.
"""

import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

# Pinned Unicode/CLDR versions (CLDR 46 ↔ Emoji 16.0).
EMOJI_VERSION = "16.0"
CLDR_RELEASE = "release-46"

EMOJI_TEST_URL = f"https://unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt"
ANNOTATIONS_URL = f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_RELEASE}/common/annotations/en.xml"
DERIVED_URL = f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_RELEASE}/common/annotationsDerived/en.xml"

FE0F = "️"  # variation selector-16

# emoji-test.txt line: "CODEPOINTS ; status # GLYPH Ev.v NAME"
_TEST_LINE = re.compile(
    r"^([0-9A-Fa-f ]+);\s*(\S+)\s*#\s*\S+\s+E\d+\.\d+\s+(.*)$"
)


def fetch(url: str) -> str:
    with urllib.request.urlopen(url) as resp:
        return resp.read().decode("utf-8")


def strip_fe0f(s: str) -> str:
    return s.replace(FE0F, "")


def normalize_name(name: str) -> str:
    """Reduce a CLDR/emoji-test name to plain space-separated words.

    "thumbs up: medium-light skin tone" -> "thumbs up medium light skin tone"
    "family: man, woman, girl"          -> "family man woman girl"
    "woman's hat"                       -> "womans hat"
    """
    name = name.replace("’", "'").replace("'", "")  # drop apostrophes
    name = re.sub(r"[^0-9A-Za-z]+", " ", name)            # other punct -> space
    return re.sub(r"\s+", " ", name).strip()


def parse_cldr(xml_text: str) -> dict:
    """Map FE0F-stripped emoji -> raw CLDR tts name."""
    xml_text = re.sub(r"<!DOCTYPE[^>]*>", "", xml_text)   # avoid external DTD
    root = ET.fromstring(xml_text)
    names = {}
    for ann in root.iter("annotation"):
        if ann.get("type") == "tts" and ann.get("cp") and ann.text:
            names[strip_fe0f(ann.get("cp"))] = ann.text.strip()
    return names


def parse_rgi(text: str) -> dict:
    """Map FE0F-stripped emoji -> emoji-test name, for the RGI set only.

    The RGI set is exactly the ``fully-qualified`` entries; ``component``
    (lone skin-tone/hair modifiers) and partially-qualified rows are skipped.
    """
    rgi = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = _TEST_LINE.match(line)
        if not m:
            continue
        cps, status, name = m.groups()
        if status != "fully-qualified":
            continue
        emoji = "".join(chr(int(c, 16)) for c in cps.split())
        rgi[strip_fe0f(emoji)] = name.strip()
    return rgi


def main() -> None:
    rgi = parse_rgi(fetch(EMOJI_TEST_URL))
    cldr = parse_cldr(fetch(ANNOTATIONS_URL))
    cldr.update(parse_cldr(fetch(DERIVED_URL)))

    table = {}
    fallback = 0
    for key, test_name in rgi.items():
        if key in cldr:
            table[key] = normalize_name(cldr[key])
        else:
            fallback += 1
            table[key] = normalize_name(test_name)

    out_path = Path(__file__).resolve().parent.parent / "Resources" / "emoji_names.json"
    out_path.write_text(
        json.dumps(table, ensure_ascii=False, sort_keys=True, indent=0) + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {len(table)} emoji to {out_path} "
        f"({fallback} used the emoji-test fallback name; "
        f"Emoji {EMOJI_VERSION} / CLDR {CLDR_RELEASE})"
    )


if __name__ == "__main__":
    main()
