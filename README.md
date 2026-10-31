<div align="center">

<img src="design/app-icon.png" alt="Crumple app icon" width="88" height="88">

# Crumple

### A little less clutter. A little more space.

A native Mac cleaner with the feel of paper.<br>
Find what you no longer need. Crumple it. Toss it away.

<sub>SwiftUI · macOS 14+ · Apple silicon & Intel · English & 简体中文</sub>

<br><br>

[Getting started](#getting-started) &nbsp; · &nbsp; [The details](#the-details) &nbsp; · &nbsp; [简体中文](README.zh-CN.md)

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/crumple-en-dark.png">
  <img src="docs/images/crumple-en-light.png" alt="Crumple Smart Clean: a warm paper background, quiet typography, and a basket of crumpled files" width="100%">
</picture>

<sub>A real SwiftUI interface, shown with demo files. Light and dark appearances.</sub>

</div>

<br>

## Make room, with a little feeling

Crumple brings a small, familiar gesture to looking after your Mac. Files become sheets of paper; a drag gathers them into a ball, and a throw sends them toward the basket. Land a shot and the file moves to the Trash. Miss, and it returns to the list.

Warm paper tones, ink-dark text, and a muted green accent give the tools room to breathe. The motion has a purpose: it shows what is being removed, what stays, and when the work is done. A printed cleanup receipt closes the loop.

## The details

| Tool | What it does |
| :--- | :--- |
| **Smart Clean** | Reviews app caches, logs, Xcode files, developer caches, installers, and old downloads. |
| **Space Lens** | Lets you explore folder sizes and follow the space down to individual files. |
| **Large Files** | Finds substantial files across your personal folders, with type, size, and last-use filters. |
| **Duplicates** | Compares file contents using full SHA-256 hashes after size and sample checks; suggests one copy to keep. |
| **Uninstaller** | Finds third-party apps and their associated files in your Library. |
| **Status & Optimize** | Shows live system readings, running apps, background items, and explicit maintenance actions. |
| **History & Undo** | Keeps cleanup receipts and can restore tracked items while they remain in the Trash and their original paths are available. |

The menu bar panel keeps useful system readings close by. The interface supports English and Simplified Chinese, with light, dark, and system appearances.

## Care in the defaults

- Scanning reads files; cleaning begins after your selection.
- **Move to Trash** is the default. Permanent deletion is a separate setting.
- Old downloads, installers, and Xcode archives start unselected.
- Caches belonging to running apps are protected from cleaning.
- A path boundary restricts cleanup to items at least two levels inside the home folder, plus apps directly inside the supported Applications folders.
- Demo mode uses generated files and its own Trash folder, so you can try the interaction in isolation.

## Getting started

Requires **macOS 14 or later** and Apple's **Command Line Tools**. The build uses system frameworks and has no third-party package dependencies.

```bash
git clone https://github.com/Jul11us/Crumple.git
cd Crumple
bash build.sh
open build/Crumple.app
```

The build produces a universal app for **Apple silicon and Intel**. To install it in Applications:

```bash
bash install.sh
```

### Try the paper first

Launch a separate demo process with generated files:

```bash
CRUMPLE_DEMO_HOME=/tmp/crumple-demo \
  "build/Crumple.app/Contents/MacOS/Crumple"
```

### Package a disk image

```bash
bash make-dmg.sh
```

This creates `build/Crumple <version>.dmg`. Builds are ad hoc signed by default; distribution with Developer ID signing and Apple notarization is supported through `notarize.sh` and requires a developer account. The current default build is not notarized.

## Under the paper

Built with **Swift, SwiftUI, and AppKit**. The scanning and cleanup engine, application state, paper drawing and motion, and native views live in separate directories under [`Sources/Crumple`](Sources/Crumple).

```bash
swift test
bash Localization/verify.sh
```

The tests cover cleanup boundaries, symbolic links, restoration, duplicate detection, and throw outcomes. Localization checks validate the built app's Chinese and English resources; run `bash build.sh` first.

For rendering previews, inspecting scans, and working on the app, see the [development guide](docs/DEVELOPMENT.zh-CN.md). Verification notes are in [`VALIDATION.md`](VALIDATION.md).

## Design notes

Crumple's identity comes from paper, a basket, and the pleasure of a small, deliberate action. The interface review drew on [unslop by Damir Sokolovsky](https://github.com/heydamir/unslop), used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Adaptation notes and attribution are recorded in [UI direction](design/UI-DIRECTION.md).

<br>

<div align="center">
<sub>Crumple · Made for a little more space.</sub>
</div>
