# Task: archive_completed_projects

## Overview

The agent has ~/Documents/Projects/ with five personal project folders. Three are complete (marked by a `DONE.txt` file inside) and two are active. The task tests whether an agent can:

1. Discover which projects are done (by inspecting folder contents for DONE.txt)
2. Apply different color tags based on project status
3. Compress done projects to zip files and move them to an Archive folder
4. Delete the original folders after archiving
5. Add descriptive Finder comments to archived zip files

This is a common personal housekeeping scenario: a user wants to tidy up their projects folder, preserving finished work as archives while keeping active projects accessible.

## End State (Goal)

```
~/Documents/Projects/
├── HomeRenovation/             [Green Finder tag — active]
└── LearnPiano/                 [Green Finder tag — active]

~/Documents/Archive/
├── VegetableGarden.zip         [comment: "Archived May 2026"]
├── BookClub2024.zip            [comment: "Archived May 2026"]
└── CookingChallenge.zip        [comment: "Archived May 2026"]
```

Done project folders (VegetableGarden, BookClub2024, CookingChallenge) must NOT exist in ~/Documents/Projects/ after completion.

## Active vs Done Projects

| Project | Status | DONE.txt |
|---------|--------|----------|
| HomeRenovation | Active | No |
| VegetableGarden | Done | Yes |
| LearnPiano | Active | No |
| BookClub2024 | Done | Yes |
| CookingChallenge | Done | Yes |

## Success Criteria

| Criterion | Points | Details |
|-----------|--------|---------|
| C1: Active projects present + Green tag | 30 | 10 pts presence + 5 pts tag, × 2 active |
| C2: Done project zips in Archive | 30 | 10 pts × 3 done projects |
| C3: Done originals deleted from Projects | 20 | 7+7+6 pts |
| C4: Zip Finder comments "Archived May 2026" | 20 | 7+7+6 pts |
| **Total** | **100** | Pass at ≥70 |

## Verification Strategy

`export_result.sh` reads:
- `active_folders_exist` — `os.path.isdir` for HomeRenovation, LearnPiano
- `done_folders_exist` — `os.path.isdir` for the 3 done projects
- `active_tags` — `mdls -name kMDItemUserTags` on active folders
- `archive_zips` — `os.listdir` on ~/Documents/Archive/ filtering *.zip
- `zip_comments` — `osascript … get comment` on each zip

## Edge Cases and Potential Issues

- The agent must open each project folder (or use Quick Look/Get Info) to find DONE.txt — it is not visible from the top-level Projects/ view without navigation.
- Compressing a folder in Finder: right-click → Compress. This creates `<FolderName>.zip` in the same location.
- Moving the zip to Archive and then deleting the original are separate steps.
- Finder comments on zip files behave the same as on folders (Get Info → Comments field or via AppleScript).
- If the agent deletes active projects, C1 scores zero for those projects — a strong penalty.
