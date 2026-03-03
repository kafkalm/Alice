# Alice

Alice is a macOS-first personal assistant focused on helping users quickly understand English sentences by extracting subject/verb/object structure.

## Product docs
- Product design (V1-V3): `docs/product/alice-product-design-v1-v3.md`
- Quick SVO Parse PRD: `docs/prd/quick-svo-parse-prd.md`

## Current code modules
- `AliceCore` (Swift library)
  - sentence splitting
  - heuristic SVO parsing
  - local-first parse orchestration with optional cloud fallback
  - OCR-only text capture with Vision OCR
  - capture-runner orchestration and event logging
- `AliceMac` (SwiftUI menu bar app)
  - global shortcut listener (`Cmd+Shift+A`)
  - focused-text capture + parse trigger
  - menu panel result rendering and floating near-cursor card

## Xcode Run
- Open `Alice.xcodeproj` in Xcode.
- Select scheme `AliceDesktop` and destination `My Mac`.
- Press `Cmd+R` to run.
- If project files need regeneration after structure changes: `xcodegen generate`.

## Stable Dev Run (Less Re-Authorization)
- Run: `./scripts/dev-run.sh`
- This script keeps a stable setup for local iteration:
  - fixed `DerivedData` path
  - fixed dev bundle id (`com.kafkalm.alice.dev`)
  - fixed Apple Development signing identity fingerprint + team id
  - fixed app install location (`~/Applications/AliceDev.app`)
- This usually avoids repeated macOS permission prompts across code iterations.
- Optional overrides:
  - `DEV_BUNDLE_ID=com.your.alice.dev ./scripts/dev-run.sh`
  - `DEV_TEAM_ID=YOURTEAMID ./scripts/dev-run.sh`
  - `DEV_CODE_SIGN_IDENTITY=<SHA1 fingerprint> ./scripts/dev-run.sh`
  - `INSTALL_DIR=/Applications ./scripts/dev-run.sh` (may require admin password)

## Development
- Build: `swift build`
- Test: `swift test`
- Run app: `swift run AliceMac`
- MVP implementation guide: `docs/development/quick-svo-mvp-setup.md`

## Legacy template docs
This repository started from the Codex + GitHub + Notion ops template. See `docs/project-ops/notion-github-codex-ops.md` for operational setup details.
