# Finder macOS Power-User Workflow Research Notes

Research conducted for the 5 new finder_env tasks. URL → insight bullets format.

---

## Tags & Color Labels

**[Mac Finder Tags: Organize Files Faster With Color Labels and Smart Folders — AppleMagazine](https://applemagazine.com/mac-finder-tags/)**
- Tags add a metadata layer without changing folder structure; Smart Folders surface files matching saved criteria in real time
- Color tags (7 fixed: Red, Orange, Yellow, Green, Blue, Purple, Gray) can be combined with named labels
- Tags can represent *status* rather than file type — a file stays in its project folder while the tag tracks its pipeline stage

**[Are Finder Tags useful metadata? — The Eclectic Light Company](https://eclecticlight.co/2023/11/04/are-finder-tags-useful-metadata/)**
- Tags stored in xattr `com.apple.metadata:_kMDItemUserTags` as a binary plist (NSArray of strings)
- Each tag string is `"<label>\n<color_index>"` where color_index is 0–7
- Tags survive copies if xattrs are preserved; stripped by some file systems (NFS) and some CLI tools — a non-obvious gotcha agents must understand
- `mdls -name kMDItemUserTags <path>` is the reliable programmatic read path

**[A little tagging automation — leancrew.com](https://leancrew.com/all-this/2018/10/a-little-tagging-automation/)**
- Shell / AppleScript / Homebrew `tag` utility can all set tags programmatically
- Named tags (not just colors) are searchable in Spotlight and usable as Smart Folder criteria
- Combining filename conventions with tags gives a two-axis organizational system

**→ Tasks using this:** `build_recipe_smart_folder`, `archive_completed_projects`, `annotate_and_index_downloads`, `curate_vacation_photo_album`

---

## Smart Folders (savedSearch)

**[Unlock the Power of SMART Folders on Your Mac — MacForce](https://www.macforce.com/blog/unlock-the-power-of-smart-folders-on-your-mac)**
- Smart Folders are virtual — they contain no files, just a saved Spotlight query
- Stored as `.savedSearch` plist files at `~/Library/Saved Searches/`
- Criteria support Boolean AND/OR/NOT; hold Option while clicking "+" for nested rules
- Auto-update in real time as files change — the defining usability win over static folders

**[Finder Tags & Smart Folders: Organise Client Files — computerskills.info](https://www.computerskills.info/mastering-finder-tags-smart-folders/)**
- Practical Smart Folder rule sets: *Kind:Document AND Tags:Active AND Last-modified:≤7d*
- Tags-as-status-board: change a tag to move the file into a different Smart Folder automatically
- Smart Folders in Finder sidebar → surfaced alongside regular folders for zero-friction access

**[Access Finder Smart Folders with AppleScript? — Apple Discussions](https://discussions.apple.com/thread/8441847)**
- `open POSIX file "/path/to/file.savedSearch"` opens the Smart Folder in a Finder window via AppleScript
- The `.savedSearch` plist can be read programmatically with `plistlib` to verify criteria without opening Finder

**→ Tasks using this:** `build_recipe_smart_folder`

---

## File Locking (UF_IMMUTABLE)

**[How to Lock Files and Folders in macOS — MakeUseOf](https://www.makeuseof.com/how-to-lock-files-on-a-mac/)**
- Finder "Locked" checkbox in Get Info sets the `uchg` (user immutable) flag — equivalent to `chflags uchg <file>`
- Locked items display a padlock badge on their icon in Finder
- Locked files cannot be modified, renamed, or deleted without explicit unlock — protects "final" deliverables

**[CHFLAGS Command — ss64.com](https://ss64.com/mac/chflags.html)**
- `chflags uchg <file>` locks; `chflags nouchg <file>` unlocks
- `ls -lO` reveals the `uchg` flag in the flags column
- Programmatic detection: `os.stat(path).st_flags & 0x00020000` (UF_IMMUTABLE bitmask)

**[Find locked files in OSX terminal — Coderwall](https://coderwall.com/p/-3hwvg/find-locked-files-in-osx-terminal)**
- `find . -flags +uchg` lists all locked files recursively — useful for verification scripts
- Locking is distinct from Unix permissions (chmod) — both can be set independently

**→ Tasks using this:** `declutter_desktop_to_projects`

---

## Photo Organization in Finder

**[Organizing a very large and disorganized photo collection — MacRumors Forums](https://forums.macrumors.com/threads/organizing-a-very-large-and-disorganized-photo-collection.2467286/)**
- Community consensus: hierarchical folders (by year/trip/event) + Finder tags for status is more durable than relying solely on Photos.app metadata
- Renaming files to `YYYY-MM-DD_IMG_nnnn.jpg` before organizing enables chronological sort in any tool
- "Highlights" subfolder per trip is a common pattern for curated best-of sets

**[How to Organize Photos on Mac — macobserver.com](https://www.macobserver.com/tips/organize-photos-on-mac/)**
- Finder color tags on trip folders signal curation status at a glance (e.g., Yellow = needs review, Green = done)
- Smart Folder for `Kind:Image AND Tag:Needs Review` surfaces all uncurated photos across trips
- Folder comments via Finder Get Info or `osascript` let you add trip summaries without a separate notes file

**[Organize photos on Mac: Smart Albums and other tricks — MacPaw](https://macpaw.com/how-to/organize-photos-app-mac)**
- Finder approach vs. Photos.app: Finder folders are tool-agnostic (work with any image editor) but lose facial recognition and Places; Photos.app adds those features but locks metadata inside its library
- Power users often maintain *both*: a Finder folder tree as the canonical archive + Photos albums for sharing

**→ Tasks using this:** `curate_vacation_photo_album`

---

## File Archiving and Project Lifecycle

**[How to organize files and folders on your Mac — Setapp](https://setapp.com/how-to/organize-files-and-folders)**
- Common personal workflow: Active → In Review → Archived project lifecycle, surfaced via tags + Smart Folders
- Archiving to `.zip` frees iCloud quota and signals "this project is done" semantically
- Spotlight comments on archives (osascript `comment of`) preserve human context that filenames lose

**[5 Smart File Organization Tricks for Mac Users in 2025 — Tokie](https://tokie.is/blog/5-smart-file-organization-tricks-every-mac-user-should-know-in-2025)**
- Desktop should be a *temporary staging area*, not a long-term storage location — the messiness of a file-littered Desktop is a primary pain point for Mac users
- Tagging files on the Desktop before moving them is the recommended power-user pattern
- Folder hierarchy inside `~/Documents` with clear naming conventions is preferred over flat Desktop dumps

**→ Tasks using this:** `archive_completed_projects`, `annotate_and_index_downloads`, `declutter_desktop_to_projects`

---

## File Comments (Spotlight Comments)

**[Using Finder labels for tagging files — macosxtips.co.uk](http://www.macosxtips.co.uk/index_files/using-finder-labels-for-tagging-files-automating-actions.php)**
- Spotlight Comments (Get Info → Spotlight Comments field) are searchable via `kMDItemComment`
- Set/read programmatically: `osascript -e 'tell application "Finder" to get comment of (POSIX file "...")'`
- Comments survive renames but are stored in `.DS_Store` metadata — stripped when copying to non-HFS+ volumes

**→ Tasks using this:** `annotate_and_index_downloads`, `archive_completed_projects`, `curate_vacation_photo_album`

---

## Hardness Levers Applied

| Lever | Tasks |
|-------|-------|
| Multi-stage pipeline (sort → tag → highlight → comment) | `curate_vacation_photo_album` |
| Declarative config artifact with correct plist structure | `build_recipe_smart_folder` |
| Audit discovery (find what belongs in each bucket) | `archive_completed_projects`, `annotate_and_index_downloads` |
| Multi-criterion file naming conventions to discover | `build_recipe_smart_folder`, `annotate_and_index_downloads` |
| Irreversible action with verification (lock) | `declutter_desktop_to_projects` |
| Cleanup + annotation in one pass | `declutter_desktop_to_projects`, `annotate_and_index_downloads` |
