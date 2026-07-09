# create_meeting_agenda

Apple Notes note-creation task. The agent must create a single note titled
`Q3 Planning Kickoff` with three specific body lines.

## Domain context

A product manager prepping a Q3 kickoff would dump bullet-list-style action
items into Notes during the meeting. The task verifies the agent can:
1. Drive Apple Notes' UI (open it, focus a new note, set the title)
2. Type multi-line content (bullets or plain lines both accepted)
3. Get specific phrases right (verifier checks exact tokens like `2026-08-15`
   and `$5M`)

## Required body lines

1. `Hire 3 senior engineers`
2. `Q3 OKR target: $5M revenue` (verifier accepts `Q3 OKR` + `$5M`/`5M revenue`)
3. `Product launch on 2026-08-15` (verifier accepts the date string anywhere
   in the body)

## How the result is captured

`export_result.sh` talks to the live Notes app via AppleScript
(`tell application "Notes" to ...` — direct app scripting, not System Events,
so TCC doesn't block it over SSH per `12_macos_environments.md`). It writes
`/tmp/create_meeting_agenda_result.json` with:

- `matching_count` — number of notes whose name == target title
- `note_body_html` / `note_body_text` — body of the first match, raw HTML
  and HTML-stripped text
- `line_hire`, `line_okr`, `line_launch` — boolean phrase flags
- `total_notes_post_start` / `other_post_start_titles` — wrong-target signal

If `matching_count == 0` and other notes were created after task start, the
verifier classifies that as wrong-target and returns 0 regardless of body
content (Pattern #2 in `03_verification_patterns.md`).

## Scoring (100 pts, pass at 60)

| Criterion | Points | What |
|-----------|-------:|------|
| C1 | 20 | Note titled exactly `Q3 Planning Kickoff` exists |
| C2 | 25 | Body contains `Hire 3 senior engineers` |
| C3 | 25 | Body contains `Q3 OKR` AND `$5M`/`5M revenue` |
| C4 | 30 | Body contains `2026-08-15` |

All criteria are binary (no partial credit). Pass threshold 60 means:
- Title + 2 of 3 content lines → pass (smallest passing combo = 70 pts)
- Title + 0 or 1 content line → fail
- Wrong target (gate fires) → 0

## Anti-gaming protections

- **Do-nothing**: `matching_count == 0 AND total_notes_post_start == 0` → 0.
- **Wrong-target**: agent wrote a differently-titled note → 0.
- **Title-fabrication-without-content**: title gate + binary content keeps
  partial credit below pass threshold (max-partial-not-passing is C1+C3 = 45).
- **Pre-existing note**: `setup_task.sh` deletes any note with the target
  title before launch, so the existence check alone implies the agent did the
  work post-setup.

## Edge cases

- **Multiple matching notes**: if the agent gets confused and creates two
  notes with the same title, verifier scores the first one's body. This is
  documented but not actively penalized (`feedback` flags it).
- **iCloud sync**: in a fresh sandbox there's no iCloud account; all notes
  go to "On My Mac". If a future env image preloads an iCloud account, the
  `whose name is X` query still works against the iCloud folder's notes.
- **Autocorrect**: `setup_apple_notes.sh` disables `NSAutomaticSpellingCorrectionEnabled`
  and related substitutions so Notes doesn't rewrite the agent's typed phrases
  before the verifier sees them.
