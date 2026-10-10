# TaskBoard

A lightweight, native macOS kanban board inspired by Trello, built with SwiftUI. It is single-user and fully offline: no account, no server, no sync. Everything stays on your Mac.

The interface is available in **English**, **Simplified Chinese** (任务看板) and **Traditional Chinese** (任務看板).

## Features

- **Multiple boards**: create, rename and delete boards from the sidebar.
- **Custom lists**:
  - A new board starts with To Do / In Progress / Done.
  - Add, delete and rename lists (double-click the title).
  - Reorder lists by dragging a whole list (anywhere except on a card). The other lists slide aside to preview the new order, and releasing places the list there. Dropping outside the board or pressing Esc cancels.
- **Cards**:
  - Each card has a title, a description and attachments.
  - Mark a card done with one click; it gets a check and a strikethrough.
  - Drag cards to reorder them or move them between lists. The card moves into place as you drag, the other cards make room, and releasing leaves it exactly where the preview showed. Dropping outside the board or pressing Esc cancels.
  - Right-click a card for quick actions: color, move, archive, delete.
- **Attachments**:
  - Add files with the file picker, drag and drop, or paste an image from the clipboard.
  - The first image becomes the card's cover, and you can choose a different one.
  - Click an attachment to open it in its default app.
- **Colors everywhere**: cards, lists and the board background each take a color. Pick from 24 presets or the system color picker (opacity supported). Text switches between black and white for contrast.
- **Markdown descriptions**:
  - Card descriptions render headings, lists, task lists, bold, italic, code, links, quotes and code blocks.
  - Double-click the description, or click **Edit** (编辑), to change it.
- **Auto-archive**: per board, done cards can archive themselves 1, 3, 7 or 30 days after completion. Set it in the board's gear menu (Board Settings).
- **Archive**:
  - Archive single cards, or all done cards in a list at once.
  - Browse, search, restore or permanently delete archived cards.
  - Deleting a list moves its cards to the archive instead of losing them.
- **Due dates & reminders**:
  - Give a card a due date and time.
  - The card badge turns orange when it's due within 24 hours, red when overdue, and green once done.
  - Optionally get a macOS notification at the due time, or 15 minutes, 1 hour or 1 day before. Clicking the notification opens the card.
- **Labels**:
  - Each board has its own colored labels; a label's name is optional.
  - A card can have several labels, shown as small pills at its top.
  - Manage labels from the card editor, or toggle them by right-clicking a card.
- **Filters**:
  - Filter a board by label (matches any selected), status (open or done), or due date (overdue, today, next 7 days, or no due date).
  - Filters combine with search. A bar above the board shows what's active and how many cards match.
- **Upcoming view**:
  - A sidebar entry that collects due cards from every board, grouped as overdue, today, tomorrow, next 7 days and later.
  - The sidebar badge counts unfinished cards that are overdue or due today.
- **Quick Look**: click an attachment, or press Space on a selected card, to preview attachments in place.
- **Keyboard shortcuts** (on the board, when no text field is being edited):

  | Key | Action |
  | --- | --- |
  | Arrow keys | Move the selection (hovering also selects) |
  | Return | Open the card |
  | Space | Quick Look the card's attachments |
  | D | Toggle done |
  | Delete | Archive |
  | N | New card in the current list |
  | Esc | Clear the selection |

  **Help → Keyboard Shortcuts** (⌘/) shows this list in the app.
- **Checklists**: add sub-tasks inside a card. The card shows progress such as `3/5`, which turns green when everything is checked.
- **Undo / Redo**: ⌘Z and ⇧⌘Z work for every board action, including deleting cards, lists and boards. All edits made in one card-editor session undo as a single step.
- **Search**: find cards by title, description or checklist items from the toolbar.
- **Smooth motion**:
  - Cards and lists animate when they move, appear or disappear, and switching boards cross-fades.
  - While dragging, the other cards or lists slide aside to preview the result.
  - With **Reduce Motion** turned on, movement is replaced by simple fades.
- **Three languages**:
  - English, Simplified Chinese and Traditional Chinese, including dates, reminders and the app name.
  - By default the app follows your system language. You can change it in **Settings → General**, or per app in System Settings → General → Language & Region → Applications.
- **Settings window** (⌘,): language, default due time and reminder for new due dates, backup retention, data location, import/export, and update preferences.
- **Import & export**:
  - **Export a board** (board gear menu, sidebar right-click, or **File → Export Current Board…**) to a `.taskboard` file containing its lists, cards (including archived ones), labels and attachments. Importing it adds a new board and never touches existing ones.
  - **Export all data** (**File → Export All Data…**) to move everything to another Mac. When importing, choose **Add as New Boards** or **Replace All Data**. Replacing backs up your current data first and can be undone with ⌘Z.
  - Use **File → Import…** (⇧⌘I), or double-click a `.taskboard` file in Finder.
- **Automatic updates**: since 1.3.0 the app updates itself through [Sparkle](https://sparkle-project.org). It checks daily, or on demand from **TaskBoard → Check for Updates…** or **Settings → Updates**.
- **Auto-save & backups**:
  - Changes are written to disk automatically.
  - A backup is taken once a day, and the last 30 are kept.
  - Use **File → Back Up Now** or **File → Restore from Backup…** to manage them.

## Download & install

1. Download `TaskBoard-x.y.z.dmg` from the [latest release](https://github.com/WinglokWong/TaskBoard/releases/latest).
2. Open the DMG and drag **TaskBoard** into **Applications**. Finder shows it as 任务看板 or 任務看板 on Chinese systems.
3. Open the app for the first time:
   - TaskBoard is not notarized by Apple, so macOS blocks it the first time with "Apple could not verify…".
   - Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the TaskBoard message.
   - Confirm, and the app opens. You only need to do this once.

   Alternatively, run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/TaskBoard.app"
   ```

Runs on macOS 14 Sonoma or later, on both Apple Silicon and Intel Macs.

Upgrading from 1.3.x happens inside the app; your existing install keeps its current file name. From 1.3.0 on, new versions are offered inside the app, so you only need to install manually once. Versions 1.2.0 and earlier don't include the updater; download 1.3.0 or later once to get it.

## Requirements (for building)

- macOS 14 Sonoma or later
- Xcode 16 / Swift 6 toolchain

## Build

```bash
./build.sh
```

This compiles a universal (arm64 + x86_64) release build, generates the app icon and packages everything into `build/TaskBoard.app` (ad-hoc signed). Drag it into `/Applications` to install.

To produce a distributable DMG:

```bash
VERSION=1.3.0 scripts/package_dmg.sh
```

This writes `build/TaskBoard-1.3.0.dmg`.

### Localization

Interface strings live in [`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings), a String Catalog that Xcode can also edit. Simplified Chinese is the source language. English and Traditional Chinese translations are kept in [`scripts/translations.py`](scripts/translations.py). App names per language are in `Resources/*.lproj/InfoPlist.strings`.

After changing interface text, run:

```bash
scripts/update_strings.sh
```

The script extracts every localizable string with the Swift compiler, syncs the catalog, and applies the translations. It lists any string that still needs an English or Traditional Chinese translation. `build.sh` compiles the catalog into the app. It also generates a Simplified Chinese table from the source strings with `scripts/source_strings.py`. Without that table, lookups made in code (such as "Today 2:00 PM" on due badges) would fall back to English on Simplified Chinese systems.

To try a language without changing your settings:

```bash
open build/TaskBoard.app --args -AppleLanguages '(en)'
```

### Releasing

Write the release notes in a Markdown file, commit everything, then run:

```bash
scripts/release.sh 1.3.0 path/to/notes.md
```

The script:

1. Builds the DMG, using the commit count as the build number. Sparkle compares build numbers, so they must always increase.
2. Signs the DMG with the Sparkle EdDSA private key.
3. Tags the release and publishes it on GitHub with the DMG attached.
4. Adds the version to [`appcast.xml`](appcast.xml) and pushes it. Running apps read this feed to find updates.

The appcast is updated last, so apps never see an update before its download exists.

> **Signing key:** the private key lives in the login Keychain of the Mac that ran Sparkle's `generate_keys`. The matching public key is in `build.sh` (`SUPublicEDKey`). Back up the private key:
>
> ```bash
> .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
> ```
>
> Store the file somewhere safe, outside this repository. Without the key, existing installs can't verify new updates.

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

Attachment files are not deleted right away when you remove a card or attachment, so undo and restore can still find them. Files no longer referenced by your data or by any backup are cleaned up on the next launch. Use **File → Show Data Folder in Finder** to jump there.

Backups only copy `data.json`; attachments stay in place. To move everything, including attachments, to another Mac, use **File → Export All Data…** instead.

### The `.taskboard` file format

A `.taskboard` file is a zip archive containing:

| Entry | Contents |
| --- | --- |
| `manifest.json` | Format name, format version, kind (`board` or `library`), app version, export date |
| `data.json` | One board, or all data |
| `attachments/` | The attachment files referenced by the data |

Imported files are treated as untrusted:

- The zip's entry list is checked for absolute paths and `..` before anything is extracted.
- Only the known entries are read, and attachment names must be plain file names.
- Boards added on import get fresh IDs and freshly named attachment files, so they never collide with existing data.

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
├── Labels.swift          # Label pills, flow layout, label picker
├── Filters.swift         # Board filter and due-date categories
├── UpcomingView.swift    # Cross-board due-date overview
├── Keyboard.swift        # Board keyboard shortcuts and help sheet
├── Markdown.swift        # Lightweight Markdown renderer for descriptions
├── Motion.swift          # Shared animation timings (respects Reduce Motion)
├── Updater.swift         # Sparkle auto-update integration
├── Localization.swift    # App language, locale and relaunch helpers
├── SettingsView.swift    # Settings window (⌘,)
├── Transfer.swift        # .taskboard export/import (file format, validation, re-identification)
├── TransferDialogs.swift # Import confirmation and result dialogs
└── ImageCache.swift      # Downsampled thumbnail cache
scripts/make_icon.swift   # Draws the app icon
scripts/package_dmg.sh    # Builds and packages a release DMG
scripts/release.sh        # Full release: DMG, signing, GitHub release, appcast
scripts/update_appcast.py # Adds a release entry to appcast.xml
scripts/update_strings.sh # Extracts strings, syncs the catalog, applies translations
scripts/translations.py   # English and Traditional Chinese translations
scripts/apply_translations.py
Resources/                # String Catalog and per-language InfoPlist.strings
appcast.xml               # Sparkle update feed (written by release.sh)
build.sh                  # Builds and packages the .app bundle
```
