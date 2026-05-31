# MisakiSwift

A Swift port of the [Misaki](https://github.com/hexgrad/misaki) grapheme-to-phoneme (G2P) library for converting English text to phonetic representations suitable for text-to-speech (TTS) engines.

## Supported Platforms

- iOS 18.0+
- macOS 15.0+
- (Other Apple platforms may work as well)

## Installation

Add MisakiSwift to your Swift Package Manager dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/mlalma/MisakiSwift", from: "1.0.1")
]
```

## Basic Usage

```swift
import MisakiSwift

// Create G2P converter (british = false for American English)
let g2p = EnglishG2P(british: false)

// Convert text to phonemes
let (phonemes, tokens) = g2p.phonemize(text: "Hello world!")
print(phonemes) // "həlˈO wˈɜɹld!"
```

## Custom Phoneme Override

Use Markdown-like syntax to specify exact pronunciations in case you don't want to use fallback network:

```swift
let g2p = EnglishG2P(british: false)
let text = "[Misaki](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models."
let (phonemes, _) = g2p.phonemize(text: text)
// "misˈɑki ɪz ɐ ʤˈitəpˈi ˈɛnʤən dəzˈInd fɔɹ kˈOkəɹO mˈɑdᵊlz."
```

## Overview

MisakiSwift is a high-quality English G2P conversion library that transforms written text into phonemes using both dictionary-based lookup and neural network fallback. It supports British and American English pronunciations and includes advanced features like stress pattern handling and custom phoneme overrides.

## Key Features

- **High Accuracy**: Combines extensive pronunciation dictionaries with neural network fallback for out-of-vocabulary words
- **Dual Dialect Support**: Supports both British and American English pronunciations
- **Advanced Text Processing**: Handles punctuation, numbers, acronyms, and complex formatting
- **Custom Phoneme Override**: Use Markdown-like syntax to specify exact pronunciations: `[word](/phonemes/)`
- **Stress Pattern Control**: Automatic stress assignment with manual override capabilities
- **Apple Ecosystem Integration**: Uses Apple's Natural Language framework instead of external dependencies like SpaCy

## Architecture

MisakiSwift consists of several key components:

- **`EnglishG2P`**: Main conversion pipeline that orchestrates tokenization, lexicon lookup, and neural network fallback
- **`Lexicon`**: Dictionary-based pronunciation lookup using gold and silver dictionaries
- **`EnglishFallbackNetwork`**: Transformer-based model (ported to run on MLX) for phoneme prediction for out-of-vocabulary words

## Key Differences from Python Misaki

1. **POS Tagging**: Uses Apple's `NaturalLanguage` framework instead of SpaCy for part-of-speech tagging
2. **Neural Network**: The BART-based fallback network is ported to run on [MLX](https://github.com/ml-explore/mlx-swift)
3. **Resource Management**: All model weights and dictionaries are bundled as resources within the Swift package

## Dependencies

- **[MLX](https://github.com/ml-explore/mlx-swift)**: Machine learning framework for the neural network component
- **NaturalLanguage**: Apple's built-in framework for text processing and POS tagging
- **MLXUtilsLibrary**: For `MToken`, used also in other parts of the ML stack

## Model Resources

The package includes pre-trained models and dictionaries:

- **BART Model Weights**: Neural network weights for phoneme prediction (US and GB variants)
- **Gold Dictionary**: High-confidence pronunciation mappings
- **Silver Dictionary**: Additional pronunciation mappings with slightly lower confidence

These resources are automatically bundled with the package and loaded at runtime.

## Emoji Names

Emoji are expanded into their spoken English names ("☀️" → *"sun emoji"*,
"❤️❤️❤️" → *"three red heart emoji"*) so they are read aloud rather than passed
to the fallback network as unknown characters. A small pause is injected around
each emoji run, and consecutive identical emoji collapse to a spoken count.

The name table (`Resources/emoji_names.json`) is generated from Unicode data:

- **RGI emoji set** — Unicode `emoji-test.txt` (UTS #51), Emoji 16.0
- **Spoken short names** — CLDR `type="tts"` annotations (CLDR release-46), the
  same names VoiceOver speaks, pre-normalized to plain space-separated words

Both files are published by Unicode under the **Unicode License v3** (SPDX:
`Unicode-3.0`), which permits redistribution provided the copyright/permission
notice is included in documentation. Regenerate the table (a manual, infrequent
step that requires network access) with:

```sh
python3 Scripts/generate_emoji_names.py
```

Bump `EMOJI_VERSION` / `CLDR_RELEASE` in that script to track newer Unicode
releases.
