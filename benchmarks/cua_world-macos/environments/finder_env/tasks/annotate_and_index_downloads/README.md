# Task: annotate_and_index_downloads

## Overview

The agent has 15 miscellaneous files in ~/Downloads spanning five content types. The task tests whether an agent can:

1. Classify files by type (PDF, image, text, media playlist, other)
2. Move files into appropriately named subfolders
3. Apply the correct color Finder tag per category
4. Write a meaningful 5-word-minimum Finder comment on every file
5. Create a plain-text index file on the Desktop summarizing the library

This is a realistic personal-use scenario: a user who has accumulated months of random downloads wants to sort, annotate, and index them in one session before the folder becomes unmanageable.

## End State (Goal)

```
~/Documents/Organized/
├── Financial/
│   ├── 2024_Tax_Return_Summary.pdf        [Blue tag, comment ≥5 words]
│   ├── Bank_Statement_March_2025.pdf      [Blue tag, comment ≥5 words]
│   └── Investment_Portfolio_Q1.pdf        [Blue tag, comment ≥5 words]
├── Photos/
│   ├── family_reunion_photo.jpg           [Yellow tag, comment ≥5 words]
│   ├── kitchen_before.jpg                 [Yellow tag, comment ≥5 words]
│   └── garden_sketch.png                  [Yellow tag, comment ≥5 words]
├── Notes/
│   ├── grocery_list.txt                   [Green tag, comment ≥5 words]
│   ├── book_recs.txt                      [Green tag, comment ≥5 words]
│   └── home_repairs.txt                   [Green tag, comment ≥5 words]
├── Media/
│   ├── workout_playlist.m3u               [Red tag, comment ≥5 words]
│   ├── relaxing_evenings.m3u              [Red tag, comment ≥5 words]
│   └── road_trip_mix.m3u                  [Red tag, comment ≥5 words]
└── Other/
    ├── hiking_trail_loop.gpx              [Gray tag, comment ≥5 words]
    ├── household_budget.xlsx              [Gray tag, comment ≥5 words]
    └── dentist_appointment.ics            [Gray tag, comment ≥5 words]

~/Desktop/File_Index.txt
  → 15 lines, each: filename | folder | comment
```

## Category → Tag Map

| Folder | Tag Color | File Types |
|--------|-----------|------------|
| Financial | Blue | .pdf |
| Photos | Yellow | .jpg, .png |
| Notes | Green | .txt |
| Media | Red | .m3u |
| Other | Gray | .gpx, .xlsx, .ics |

## Success Criteria

| Criterion | Points | Details |
|-----------|--------|---------|
| C1: Files in correct subfolder | 30 | 2 pts × 15 files |
| C2: Color tags correct | 20 | proportional (15 files) |
| C3: Finder comments ≥5 words | 25 | proportional (15 files) |
| C4: File_Index.txt complete | 25 | exists (5) + 15 pipe-sep lines (10) + all filenames (10) |
| **Total** | **100** | Pass at ≥70 |

## Verification Strategy

`export_result.sh` reads:
- `files_by_folder` — `os.listdir` per subfolder
- `tags_by_file` — `mdls -name kMDItemUserTags` per file
- `comments_by_file` — `osascript … get comment` per file
- `index_exists` — `os.path.isfile` on ~/Desktop/File_Index.txt
- `index_lines` — raw lines of the index file

Verifier checks correct routing (2 pts/file), tag color match (proportional), comment word count (≥5), and index structure (pipe separator, all 15 filenames present).

## Edge Cases and Potential Issues

- Finder comments must be set via Get Info (⌘I) → Comments field or via AppleScript. They are not the same as Finder labels.
- Gray is a valid macOS Finder tag color. It may appear as "Gray" in mdls output.
- The index file format `filename | folder | comment` is flexible — verifier checks for `|` separator and for all 15 filenames appearing anywhere in the file.
- If the agent adds extra Finder comments that omit the 5-word requirement, proportional scoring applies — no all-or-nothing fail.
