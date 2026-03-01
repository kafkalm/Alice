# Quick SVO MVP Development Guide

## Prerequisites
- macOS 14+
- Xcode command line tools
- Swift 6.2+

## Build and Test
```bash
swift build
swift test
```

## Run the menu bar app
```bash
swift run AliceMac
```

The app launches as a menu bar utility named **Alice**. Open it from the menu bar icon, paste an English paragraph, and click **Parse** to see sentence-by-sentence S/V/O output.

## Current implementation scope
- `AliceCore`:
  - sentence splitting (`NLTokenizerSentenceSplitter`)
  - local SVO parsing (`HeuristicSVOParser`)
  - fallback orchestration (`QuickSVOService`)
  - event logging (`LocalEventLogger`)
- `AliceMac`:
  - menu bar UI for manual paragraph parsing
- Automated tests:
  - sentence splitting
  - parser behavior
  - fallback routing

## Next implementation steps
- wire global shortcut listener
- implement AX-first text capture
- add OCR fallback for inaccessible text surfaces
- render floating result card near cursor
