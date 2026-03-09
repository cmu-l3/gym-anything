# Task: secure_bookmark_management

## Domain Context

Investigative journalists and researchers use Tor Browser to maintain a curated library of trusted onion services and clearnet privacy resources for ongoing investigations. Creating an organized, named bookmark structure is a standard professional workflow for tracking verified sources across multiple stories. This task tests the agent's ability to navigate multiple sites via Tor, create organized bookmark folders with exact names, and bookmark pages with specific titles — all while maintaining correct URL attribution (e.g., the .onion version vs. clearnet version of DuckDuckGo).

## Goal

Build an organized research bookmark library in Tor Browser:
1. Visit `https://check.torproject.org/` to verify Tor is active
2. Visit `https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/` (DuckDuckGo onion)
3. Search for "press freedom index reporters without borders" on DuckDuckGo onion
4. Create bookmark folder named exactly **"Secure Research Sources"**
5. Bookmark DuckDuckGo onion homepage as **"DuckDuckGo Private Search"** in that folder
6. Bookmark check.torproject.org as **"Tor Exit Node Checker"** in that folder
7. Create a second folder named exactly **"Press Freedom Research"**
8. Bookmark one DuckDuckGo search result in "Press Freedom Research"

## Difficulty

**hard** — Requires visiting two distinct sites, creating two bookmark folders with exact names, setting specific bookmark titles, and performing a search to discover a result to bookmark. The agent must navigate the bookmark management UI which differs from standard browser bookmark UIs.

## Success Criteria

- **Pass threshold**: 60+ points AND folder "Secure Research Sources" exists (required gate)
- Full score: 100 points across 10 criteria

## Scoring Breakdown

| Criterion | Points | Required |
|-----------|--------|----------|
| check.torproject.org in history | 10 | No |
| DuckDuckGo onion in history | 10 | No |
| DuckDuckGo onion search in history | 10 | No |
| Folder "Secure Research Sources" exists | 15 | Yes (gate) |
| DuckDuckGo onion bookmarked in "Secure Research Sources" | 15 | No |
| DuckDuckGo bookmark title = "DuckDuckGo Private Search" | 10 | No |
| check.torproject.org in "Secure Research Sources" | 10 | No |
| Tor checker title = "Tor Exit Node Checker" | 5 | No |
| Folder "Press Freedom Research" exists | 10 | No |
| ≥1 bookmark in "Press Freedom Research" | 5 | No |

## Verification Strategy

**Primary**: Query `places.sqlite` from the Tor Browser profile:
- `moz_bookmarks` table: bookmark titles, folder structure (parent-child relationships)
- `moz_places` table: URLs associated with bookmarks and history
- `moz_historyvisits` table: visit timestamps

The export script copies `places.sqlite` from the VM (handling WAL mode) and queries it using Python's `sqlite3` module.

## Starting State

Tor Browser is launched and connected to the Tor network. No custom bookmarks exist. Browser history is empty.

## Edge Cases

- Tor Browser's bookmark UI: Ctrl+D to add a bookmark, Ctrl+Shift+B for bookmark manager, or use the star icon in the URL bar
- Folder creation in Tor Browser: When adding a bookmark (Ctrl+D), click "Choose..." to select or create a folder
- The DuckDuckGo .onion URL must be bookmarked, NOT the clearnet DuckDuckGo URL
- Bookmark titles must exactly match the required strings (case-sensitive)
- places.sqlite may be locked while browser is running; export script uses WAL copy
- The DuckDuckGo search URL includes query parameters (e.g., `?q=press+freedom+index`)
