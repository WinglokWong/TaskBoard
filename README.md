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
- **Due dates & reminders**:
  - Give a card a due date and time.
  - The card badge turns orange when it's due within 24 hours, red when overdue, and green once done.
  - Optionally get a macOS notification at the due time, or 15 minutes, 1 hour or 1 day before. Clicking the notification opens the card.
- **Checklists**: add sub-tasks inside a card. The card shows progress such as `3/5`, which turns green when everything is checked.
- **Undo / Redo**: ⌘Z and ⇧⌘Z work for every board action, including deleting cards, lists and boards. All edits made in one card-editor session undo as a single step.
- **Search**: filter cards by title, description or checklist items from the toolbar.
- **Auto-save & backups**:
  - Changes are written to disk automatically.
  - A backup is taken once a day, and the last 30 are kept.
  - Use **File → Back Up Now** (立即备份) or **File → Restore from Backup…** (从备份恢复…) to manage them.

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
| `Backups/` | Daily and manual backups of `data.json` |

Loading is tolerant: missing or unknown fields fall back to defaults, so data saved by older versions keeps working. If `data.json` truly can't be read, the app keeps a copy in `Backups/` (marked as unreadable), starts a fresh board, and tells you where the copy is.

Attachment files are not deleted right away when you remove a card or attachment, so undo and restore can still find them. Files no longer referenced by your data or by any backup are cleaned up on the next launch. Use **File → Show Data Folder in Finder** (在 Finder 中显示数据文件夹) to jump there.

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
├── BackupsView.swift     # Backup list and restore
├── Notifications.swift   # Due-date reminders (UserNotifications)
└── ImageCache.swift      # Downsampled thumbnail cache
scripts/make_icon.swift   # Draws the app icon
scripts/package_dmg.sh    # Builds and packages a release DMG
build.sh                  # Builds and packages the .app bundle
```
