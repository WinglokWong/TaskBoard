# TaskBoard

A lightweight, native macOS kanban board inspired by Trello, built with SwiftUI. It is single-user and fully offline: no account, no server, no sync. Everything stays on your Mac.

The app's interface is in Chinese (app name: 任务看板).

## Features

- **Multiple boards**: create, rename and delete boards from the sidebar.
- **Custom lists**: starts with To Do / In Progress / Done. You can rename lists (double-click the title), add, delete and reorder them.
- **Cards**:
  - Each card has a title, a description and attachments.
  - Mark a card done with one click; it gets a check and a strikethrough.
  - Drag cards between lists, or onto another card to reorder.
  - Right-click a card for quick actions: color, move, archive, delete.
- **Attachments**:
  - Add files with the file picker, drag and drop, or paste an image from the clipboard.
  - The first image becomes the card's cover, and you can choose a different one.
  - Click an attachment to open it in its default app.
- **Colors everywhere**: cards, lists and the board background each take a color. Pick from 24 presets or the system color picker (opacity supported). Text switches between black and white for contrast.
- **Archive**:
  - Archive single cards, or all done cards in a list at once.
  - Browse, search, restore or permanently delete archived cards.
  - Deleting a list moves its cards to the archive instead of losing them.
- **Search**: filter cards by title or description from the toolbar.
- **Auto-save**: changes are written to disk automatically.

## Download & install

1. Download `TaskBoard-x.y.z.dmg` from the [latest release](https://github.com/WinglokWong/TaskBoard/releases/latest).
2. Open the DMG and drag **任务看板** into **Applications**.
3. Open the app for the first time:
   - TaskBoard is not notarized by Apple, so macOS blocks it the first time with "Apple could not verify…".
   - Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the TaskBoard message.
   - Confirm, and the app opens. You only need to do this once.

   Alternatively, run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/任务看板.app"
   ```

Runs on macOS 14 Sonoma or later, on both Apple Silicon and Intel Macs.

## Requirements (for building)

- macOS 14 Sonoma or later
- Xcode 16 / Swift 6 toolchain

## Build

```bash
./build.sh
```

This compiles a universal (arm64 + x86_64) release build, generates the app icon and packages everything into `build/任务看板.app` (ad-hoc signed). Drag it into `/Applications` to install.

To produce a distributable DMG:

```bash
VERSION=1.0.0 scripts/package_dmg.sh
```

This writes `build/TaskBoard-1.0.0.dmg`.

For development you can also run it directly:

```bash
swift run
```

## Data storage

All data lives in `~/Library/Application Support/TaskBoard/`:

| Path | Contents |
| --- | --- |
| `data.json` | Boards, lists and cards (human-readable JSON) |
| `Attachments/` | Copies of attached files |

If `data.json` ever fails to load, it is backed up as `data.corrupt-<timestamp>.json` before a fresh board is created, so nothing is silently overwritten. Use **File → Show Data Folder in Finder** (在 Finder 中显示数据文件夹) to jump there.

## Project structure

```
Sources/TaskBoard/
├── TaskBoardApp.swift    # App entry, window, sidebar (ContentView)
├── Models.swift          # Board / BoardColumn / Card / Attachment
├── Store.swift           # State, persistence and all mutations
├── Colors.swift          # RGBA color model, palette, color picker view
├── BoardView.swift       # Board canvas, toolbar, add-list
├── ColumnView.swift      # A list with its cards
├── CardView.swift        # Card tile, drag & drop, context menu
├── CardEditorView.swift  # Card detail sheet and attachments
├── ArchiveView.swift     # Archived cards browser
└── ImageCache.swift      # Downsampled thumbnail cache
scripts/make_icon.swift   # Draws the app icon
scripts/package_dmg.sh    # Builds and packages a release DMG
build.sh                  # Builds and packages the .app bundle
```
