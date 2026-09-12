# Landing Page

## Purpose and Scope
Static GitHub Pages landing page for MusicPlayground. Parent: [project design](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Owns product introduction, approved visual presentation, and source-install navigation. The native app and SwiftMusic own music execution. This page does not execute Swift or play audio.

## Related Designs
The [project design](../DESIGN.md) owns product capabilities. [README](../README.md) owns current source-distribution requirements and install commands.

## Architecture
```text
Browser -> index.html + styles.css + site.js -> local image assets
                                         -> GitHub source / release / documentation
```

## Contracts and Invariants
- Relative asset URLs work under the repository subpath and at a domain root.
- The central image is an unmodified native app capture. Logo pixels are cropped from the user-approved header, not redrawn.
- Source preview, macOS/Swift requirements and install commands match README.
- Primary navigation and installation work without JavaScript. Decorative SVG is hidden from accessibility APIs; motion respects reduced-motion preferences.
- Mobile layout retains legible text, accessible controls, and no page-level horizontal overflow.

## Verification and Change Impact
Run `node --test --test-timeout=10000 Scripts/test-landing-page.mjs` from the project root. Inspect desktop and mobile renderings, keyboard focus, anchor navigation, copy success/failure and all local asset requests. Product version changes require checking copy and installation commands against README. No native rebuild is needed for static website changes.

## Publishing
Serve this directory with any static server. GitHub Pages can use main /docs with its native branch publishing. GitHub Pages is enabled at `https://1amageek.github.io/MusicPlaygournd/`, publishing main /docs over HTTPS with user authorization. No package installation or build step is required.

## Asset Provenance
- `musicplayground-symbol.png`: crop of the user-provided `exec-5b0d546d-34f9-4a4a-b9d0-4dea2bb16a5f.png`, top 65, left 535, height 575, width 675. Original retained in `../Assets/musicplayground-header.png`.
- `musicplayground-app.png`: User-supplied screenshot `スクリーンショット 2026-09-12 11.47.44.png` of LiveSet051 running both template decks, preserved unchanged at 1353 × 985 pixels. No synthesized UI or substituted code.

- `og-image.png`: unchanged copy of the approved `../Assets/musicplayground-header.png` (1774 × 887). Open Graph, canonical and X card URLs target `https://1amageek.github.io/MusicPlaygournd/`; the public site serves this image directly for social crawlers.
