# Notices and licenses

EPS Preview's own source code is licensed under the **MIT License**
(see [LICENSE](LICENSE)).

## Bundled Ghostscript (release builds only)

The downloadable release (`.dmg`) bundles a self-contained build of
**Ghostscript**, which is licensed under the **GNU Affero General Public
License v3.0 (AGPL-3.0)**.

- Ghostscript home page: https://www.ghostscript.com/
- Source code: https://github.com/ArtifexSoftware/ghostpdl-downloads
  (the exact build bundled here is the one distributed by Homebrew:
  `brew install ghostscript`).

When you **build from source** (`scripts/build.sh`) instead of using a
release, Ghostscript is **not** bundled — the app calls the copy you install
yourself via Homebrew — so the build-from-source app is MIT all the way down.

Because the release binary combines this MIT code with AGPL Ghostscript, the
**release artifact as distributed is covered by the AGPL-3.0** with respect to
Ghostscript. The corresponding Ghostscript source is available at the links
above.
