# Quick SVO MVP Development Guide

## Prerequisites
- macOS 14+
- Xcode command line tools
- Swift 6.2+

## Permissions for runtime testing
For capture from other applications, grant Alice:
- Accessibility permission
- (future OCR path) Screen Recording permission

## Build and Test
```bash
swift build
swift test
```

## Run the menu bar app
```bash
swift run AliceMac
```

The app launches as a menu bar utility named **Alice**.

## Quick start
1. Click Alice in the menu bar.
2. Use `Capture + Parse (⌘⇧A)` for focused app capture, or type text and press `Parse Input`.
3. Review sentence-by-sentence Subject / Verb / Object results.

## Current implementation scope
- `AliceCore`:
  - sentence splitting (`NLTokenizerSentenceSplitter`)
  - local SVO parsing (`HeuristicSVOParser`)
  - local-first fallback orchestration (`QuickSVOService`)
  - capture pipeline runner (`QuickSVOCaptureRunner`)
  - AX-first capture provider (`AccessibilityFirstTextCaptureProvider`)
  - language hint detection (`NaturalLanguageHintProvider`)
  - event logging (`LocalEventLogger`)
- `AliceMac`:
  - menu bar UI
  - global shortcut monitor (`Cmd+Shift+A`)
  - focused-app capture + parse integration
- Automated tests:
  - sentence splitting
  - parser behavior
  - fallback routing
  - AX/OCR capture strategy routing
  - capture-runner orchestration

## Next implementation steps
- implement real OCR reader fallback (currently `NoopOCRTextReader`)
- add floating near-cursor result card instead of menu-panel-only rendering
- add permission diagnostics and in-app onboarding flow
- improve parser accuracy for subordinate clauses and passive voice
