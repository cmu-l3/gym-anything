# Task: download_tor_documentation

## Domain Context

Security researchers, trainers, and protocol implementers routinely download official Tor Project specifications for offline reference. The Tor Project maintains a public specification site (`spec.torproject.org`) with protocol documents. Obtaining the official directory protocol specification for use in a training workshop is a realistic workflow requiring the researcher to navigate the specifications index, identify the correct document, download it, save it with a specific filename, bookmark the resource for future reference, and additionally review background history on the Tor Project.

## Goal

1. Navigate to `https://spec.torproject.org/` (Tor Protocol Specifications index)
2. Download the **"Tor directory protocol, version 3"** specification file (dir-spec.txt or similar)
3. Save the downloaded file to `/home/ga/Documents/tor-dir-spec.txt`
4. Visit `https://www.torproject.org/about/history/` to read about Tor's history
5. Bookmark `https://spec.torproject.org/` with the title **"Tor Protocol Specifications"**
6. Optionally: configure the download directory to `/home/ga/Documents/` in Settings

## Difficulty

**hard** — Requires navigating a real documentation site, locating the correct downloadable specification among multiple listed specs, downloading it, renaming/moving the file to the exact required path, visiting a second URL, and bookmarking with an exact title.

## Success Criteria

- **Pass threshold**: 60+ points AND file exists at correct path (required gate)
- Full score: 100 points across 7 criteria

## Scoring Breakdown

| Criterion | Points | Required |
|-----------|--------|----------|
| File exists at `/home/ga/Documents/tor-dir-spec.txt` | 30 | Yes (gate) |
| File created after task start | 15 | No |
| File contains Tor specification content (>1KB) | 15 | No |
| spec.torproject.org in browser history | 15 | No |
| torproject.org/about/history in browser history | 10 | No |
| spec.torproject.org bookmarked | 10 | No |
| Bookmark title = "Tor Protocol Specifications" | 5 | No |

## Verification Strategy

**Primary (file)**: Check `/home/ga/Documents/tor-dir-spec.txt` for existence, modification timestamp vs. task start, size (>1KB), and content containing "tor"/"directory"/"protocol"/"spec" keywords.

**Secondary (history + bookmarks)**: Query `places.sqlite` for history visits to the required URLs and bookmarks.

## Starting State

Tor Browser is launched and connected. `/home/ga/Documents/` exists and is empty (no `tor-dir-spec.txt`). No bookmarks for spec.torproject.org exist.

## Edge Cases

- The file may be downloaded to `/home/ga/Downloads/` by default — the agent must move/rename it to `/home/ga/Documents/tor-dir-spec.txt`
- Alternative: Configure the download directory to `/home/ga/Documents/` before downloading (Settings → General → Files and Applications)
- The spec page may list multiple documents; the agent must select the "directory protocol v3" specifically
- File may be named `dir-spec.txt` upon download — it needs to be renamed to `tor-dir-spec.txt`
- The spec file is a plain text file and should be >1KB in size
- `places.sqlite` may be WAL-locked while browser is running; export handles this with a copy
