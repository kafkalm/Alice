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
  - event logging contracts and local JSONL logger
- `AliceMac` (SwiftUI menu bar app)
  - MVP UI for paragraph input + S/V/O result output

## Development
- Build: `swift build`
- Test: `swift test`
- Run app: `swift run AliceMac`
- MVP implementation guide: `docs/development/quick-svo-mvp-setup.md`

## Legacy template docs
This repository started from the Codex + GitHub + Notion ops template. See `docs/project-ops/notion-github-codex-ops.md` for operational setup details.
