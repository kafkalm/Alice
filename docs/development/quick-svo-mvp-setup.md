# Quick SVO MVP Development Guide

## Prerequisites
- macOS 14+
- Xcode command line tools
- Swift 6.2+

## Permissions for runtime testing
For cross-app capture and OCR fallback, grant Alice:
- Accessibility permission
- Screen Recording permission

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
2. Hover text in any app and press `Cmd+Shift+A`.
3. Alice captures text (AX first, OCR fallback), parses S/V/O, and shows a floating result card near the cursor.
4. Open the menu panel for full sentence-by-sentence details.

## Current implementation scope
- `AliceCore`:
  - sentence splitting (`NLTokenizerSentenceSplitter`)
  - local SVO parsing (`HeuristicSVOParser`)
  - local-first fallback orchestration (`QuickSVOService`)
  - capture-runner orchestration (`QuickSVOCaptureRunner`)
  - AX-first capture provider (`AccessibilityFirstTextCaptureProvider`)
  - OCR fallback (`VisionOCRTextReader` with Quartz screen capture + Vision recognition)
  - language hint detection (`NaturalLanguageHintProvider`)
  - event logging (`LocalEventLogger`)
- `AliceMac`:
  - menu bar UI
  - global shortcut monitor (`Cmd+Shift+A`)
  - focused-app capture + parse integration
  - floating near-cursor result panel
- Automated tests:
  - sentence splitting
  - parser behavior
  - fallback routing
  - AX/OCR capture strategy routing
  - capture-runner orchestration
  - OCR reader behavior with injected capture/recognition stubs

## Known limitations
- OCR capture uses `CGWindowListCreateImage` (deprecated in macOS 14+); migration to ScreenCaptureKit is recommended.
- No permission onboarding UI yet; permissions must be granted from System Settings.
- Floating card is read-only and auto-dismisses after a short timeout.

## Next implementation steps
- migrate OCR capture to ScreenCaptureKit
- add explicit permission diagnostics and onboarding flow
- add close/pin actions to floating result card
- improve parser accuracy for subordinate clauses and passive voice
