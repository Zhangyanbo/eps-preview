# EPS Preview

Restore **spacebar Quick Look** and **Finder thumbnails** for `.eps` / `.ps`
files on modern macOS — the EPS support Apple removed back in macOS Ventura,
and which broke entirely once legacy Quick Look plugins stopped loading in
macOS Sequoia / Tahoe.

Select an EPS file in Finder, press **Space**, and see the full figure.
Finder icons show the real figure instead of a blank document.

<!-- 中文速览见底部 -->

## How it works

macOS 15 (Sequoia) and 26 (Tahoe) only register Quick Look extensions that
are **sandboxed** — but a sandboxed extension can't freely run Ghostscript.
EPS Preview solves this with a small, robust architecture:

```
EPSPreview.app
├── EPSPreview            host app (one-screen "installed" window)
├── EPSQuickLook.appex    sandboxed Quick Look preview  (spacebar)
├── EPSThumbnail.appex    sandboxed Finder thumbnails
└── RenderService.xpc     UNSANDBOXED helper, embedded in each extension
```

The sandboxed extensions hand an EPS path to the embedded, **unsandboxed**
`RenderService`, which runs your system **Ghostscript** (`gs`) to convert it
to PDF and returns the bytes. The extension then displays the PDF with
PDFKit. Because the render happens in the unsandboxed helper, there are no
sandbox gymnastics around executing `gs` or reading files.

Ghostscript is **not bundled** — EPS Preview uses the copy you install via
Homebrew. That keeps this project small and MIT-licensed, and always uses an
up-to-date `gs`.

## Install

### Option A — Download (recommended, nothing to build)

1. Download `EPSPreview-x.y.z.dmg` from the
   [**Releases**](https://github.com/Zhangyanbo/eps-preview/releases) page.
2. Open the `.dmg` and drag **EPSPreview.app** onto **Applications**.
3. Open it once. macOS will block it the first time because the app isn't
   Apple-notarized — go to **System Settings → Privacy & Security**, scroll
   down, and click **Open Anyway**, then confirm. (You only do this once.)
4. Select any `.eps` / `.ps` file in Finder and press **Space**.

The release is **self-contained** — Ghostscript is bundled, so you do **not**
need Homebrew or any other install. Works on macOS 14+ (Apple Silicon).

### Option B — Build from source

Requirements: Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) + [Homebrew](https://brew.sh) Ghostscript
(`brew install ghostscript`).

```bash
git clone https://github.com/Zhangyanbo/eps-preview.git
cd eps-preview
bash scripts/build.sh      # builds + ad-hoc signs (no Apple Developer account needed)
bash scripts/install.sh    # installs to /Applications, registers
```

A source build is **not** self-contained: it calls your Homebrew `gs` at
runtime (keeping the build MIT all the way down). To produce a self-contained,
shareable `.dmg` like the release, run `bash scripts/package-release.sh`.

> Why "Open Anyway"? Removing that one-time prompt entirely requires an Apple
> Developer Program membership ($99/yr) to notarize the app. The project is
> otherwise free and needs no account to build, sign, or run.

## Uninstall

```bash
bash scripts/uninstall.sh
```

## Existing files still show a blank icon?

Finder caches icons aggressively. After installing, force a refresh:

```bash
bash scripts/refresh-thumbnails.sh
```

New EPS files always get thumbnails immediately.

## Project layout

| Path | What |
|------|------|
| `Sources/Host` | Host app (SwiftUI status window) |
| `Sources/QuickLook` | Quick Look preview extension |
| `Sources/Thumbnail` | Thumbnail extension |
| `Sources/RenderService` | Unsandboxed XPC render helper (runs `gs`) |
| `Sources/Shared` | XPC protocol + client shared by the extensions |
| `scripts/` | Build / install / uninstall / thumbnail-refresh |
| `project.yml` | XcodeGen project definition |

The `.xcodeproj` is generated from `project.yml` by `scripts/build.sh` and is
intentionally not committed.

## License

This project's code is **MIT** — see [LICENSE](LICENSE).

Build-from-source uses your own Homebrew Ghostscript (nothing AGPL is
distributed). The downloadable **release** bundles a self-contained
Ghostscript, which is **AGPL-3.0**; see [NOTICE.md](NOTICE.md) for details and
source links.

---

## 中文速览

在新版 macOS 上恢复 `.eps` / `.ps` 文件的**空格预览**和**访达缩略图**功能
（Apple 从 Ventura 起移除了 EPS 支持，Sequoia/Tahoe 又彻底停用了旧式 Quick
Look 插件）。

**原理**：macOS 15/26 只接受**沙盒化**的 Quick Look 扩展，但沙盒里又没法直接
跑 Ghostscript。本项目用一个内置的**非沙盒 XPC 服务**来调用你系统里的
Ghostscript 渲染 EPS→PDF，再由扩展用 PDFKit 显示，干净地绕开了沙盒限制。
Ghostscript 不打包进来，用你 Homebrew 装的那份。

**安装**：
```bash
brew install ghostscript xcodegen   # 若未安装
git clone https://github.com/Zhangyanbo/eps-preview.git
cd eps-preview
bash scripts/build.sh && bash scripts/install.sh
```
装好后在访达里选中 `.eps` 文件按**空格**即可预览。旧文件图标若没刷新，运行
`bash scripts/refresh-thumbnails.sh`。
