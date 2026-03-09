# Task: multi_circuit_threat_intelligence

## Domain Context

Threat intelligence analysts at cybersecurity firms routinely research multiple threat actor groups, malware families, or attack campaigns using Tor Browser to protect their firm's identity from attribution. When researching two competing or unrelated threat groups, strict identity separation is essential — using the same Tor circuit for both research threads could allow monitored sites to correlate the analyst's interests. The "New Identity" feature in Tor Browser creates a completely fresh session (new circuit, cleared cookies, closed windows) that separates the two research threads.

## Goal

Conduct two independent threat intelligence research sessions with strict identity separation:

**Thread 1 — Ransomware Research**:
1. Visit `https://check.torproject.org/` to verify and document the current exit node
2. Search DuckDuckGo onion for "ransomware groups 2024 threat landscape"
3. Create bookmark folder **"Threat Intel - Ransomware"** and bookmark the search results page
4. Save research notes to `/home/ga/Documents/ransomware_research_notes.txt`

**Identity Reset**:
5. Use **New Identity** (hamburger menu → New Identity) to reset all circuits and clear session state

**Thread 2 — Phishing Infrastructure Research**:
6. Visit `https://check.torproject.org/` again to verify a new exit node IP
7. Search DuckDuckGo onion for "phishing infrastructure takedown reports 2024"
8. Create bookmark folder **"Threat Intel - Phishing"** and bookmark the search results page
9. Save research notes to `/home/ga/Documents/phishing_research_notes.txt`

## Difficulty

**very_hard** — Requires two complete research threads, four distinct browser actions (search, bookmark, save file, new identity), strict folder naming, two separate text files, and the New Identity reset between sessions. The "New Identity" operation closes all windows and requires the agent to reconnect.

## Success Criteria

- **Pass threshold**: 60+ points AND BOTH folders "Threat Intel - Ransomware" AND "Threat Intel - Phishing" exist
- Full score: 100 points across 10 criteria

## Scoring Breakdown

| Criterion | Points | Required |
|-----------|--------|----------|
| check.torproject.org in history | 10 | No |
| DuckDuckGo ransomware search in history | 10 | No |
| Folder "Threat Intel - Ransomware" exists | 15 | Yes (gate) |
| Bookmark in "Threat Intel - Ransomware" | 10 | No |
| ransomware_research_notes.txt exists and non-empty | 10 | No |
| check.torproject.org visited 2+ times (New Identity evidence) | 10 | No |
| DuckDuckGo phishing search in history | 10 | No |
| Folder "Threat Intel - Phishing" exists | 15 | Yes (gate) |
| Bookmark in "Threat Intel - Phishing" | 5 | No |
| phishing_research_notes.txt exists and non-empty | 5 | No |

## Verification Strategy

**Primary (bookmarks + history)**: Query `places.sqlite` for:
- Folder names in `moz_bookmarks` (type=2)
- Bookmarks in correct parent folders
- History visits to check.torproject.org (count ≥2 proves New Identity was used)
- History containing DuckDuckGo onion URLs with search terms

**Secondary (files)**: Check `/home/ga/Documents/` for both text files, verify modification timestamps after task start, verify non-empty content.

## Starting State

Tor Browser is launched and connected. Both target text files do NOT exist (setup removes any stale copies). No custom bookmark folders exist.

## Edge Cases

- "New Identity" closes ALL open Tor Browser windows — the agent must reopen the browser and reconnect to Tor for Thread 2
- After New Identity, the browser may take 1-2 minutes to reconnect to Tor
- Browser history is NOT cleared by New Identity (only cookies and session are cleared) — this is why 2 visits to check.torproject.org are detectable
- The DuckDuckGo search URL contains the query string, so "ransomware" and "phishing" searches appear as distinct URLs in history
- Text files can be saved using any method: the browser's "Save page as" text option, opening a terminal and using echo/nano, or using a text editor from the desktop
- Bookmark folder names are case-sensitive: "Threat Intel - Ransomware" (not "Threat Intelligence" or "Ransomware Intel")
