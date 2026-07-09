# Task: curate_vacation_photo_album

## Overview

The agent has a ~/Downloads folder containing 24 JPEG vacation photos from three distinct trips. The photos use a date-prefixed naming convention (`YYYY-MM-DD_IMG_NNNN.jpg`) that makes the trip and date recoverable purely from the filename.

The task tests whether an agent can:
1. Classify photos by trip based on filename date ranges
2. Create a structured album hierarchy under ~/Pictures/
3. Select the 3 most recent photos per trip for a Highlights subfolder
4. Apply macOS Finder color tags to trip folders
5. Set Finder comments on those folders

This is a common personal scenario: a user returning from travel wants to organize their downloaded phone photos into a permanent library before the Downloads folder becomes chaotic.

## End State (Goal)

```
~/Pictures/Family Trips/
├── Grand Canyon 2019/          [Blue Finder tag]
│   ├── (8 JPEG files — 2019-07-10 through 2019-07-20)
│   └── Highlights/
│       ├── 2019-07-17_IMG_0256.jpg
│       ├── 2019-07-19_IMG_0312.jpg
│       └── 2019-07-20_IMG_0389.jpg
├── Pacific Coast 2021/         [Green Finder tag]
│   ├── (8 JPEG files — 2021-04-01 through 2021-04-10)
│   └── Highlights/
│       ├── 2021-04-08_IMG_1222.jpg
│       ├── 2021-04-09_IMG_1267.jpg
│       └── 2021-04-10_IMG_1311.jpg
└── New England 2023/           [Red Finder tag]
    ├── (8 JPEG files — 2023-08-18 through 2023-08-28)
    └── Highlights/
        ├── 2023-08-25_IMG_2227.jpg
        ├── 2023-08-26_IMG_2271.jpg
        └── 2023-08-28_IMG_2316.jpg
```

Each trip folder must also have a Finder comment naming the destination and month/year (e.g., "Grand Canyon July 2019").

## Success Criteria

| Criterion | Points | Details |
|-----------|--------|---------|
| C1: Trip folders exist | 15 | 5 pts × 3 folders |
| C2: All 24 photos in correct trip folder | 48 | 2 pts per file |
| C3: Color tags on trip folders | 21 | 7 pts × 3 (Blue/Green/Red) |
| C4: Highlights subfolder with 3 most-recent | 12 | 4 pts per complete trip set |
| C5: Finder comments with trip name + date | 4 | 2+1+1 pts |
| **Total** | **100** | Pass at ≥70 |

## Verification Strategy

`export_result.sh` reads:
- `gc_files`, `pc_files`, `ne_files` — `find` in each trip folder (non-recursive, .jpg only)
- `gc_highlights`, `pc_highlights`, `ne_highlights` — `find` in each Highlights subfolder
- `gc_tag`, `pc_tag`, `ne_tag` — `mdls -name kMDItemUserTags` → regex extract
- `gc_comment`, `pc_comment`, `ne_comment` — `osascript … get comment`
- `gc_folder_exists`, `pc_folder_exists`, `ne_folder_exists` — `os.path.isdir`

Verifier checks each field against ground truth.

## Seeded Data

24 minimal JPEG stubs (3-byte SOI+EOI) with names and mtimes set to match the dates:
- Grand Canyon: 2019-07-10 to 2019-07-20 (8 files)
- Pacific Coast: 2021-04-01 to 2021-04-10 (8 files)
- New England: 2023-08-18 to 2023-08-28 (8 files)

## Edge Cases and Potential Issues

- Agent might not distinguish Grand Canyon from Pacific Coast; trips are identifiable purely by filename year.
- Agent might put highlights in the wrong trip or select wrong "most recent" files — graded proportionally.
- Finder tags on non-existent folders return empty; verifier handles this gracefully.
- TCC "Files and Folders" dialog may appear on first Finder access to ~/Pictures — agent must click Allow.
