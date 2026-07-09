# Task: declutter_desktop_to_projects

## Overview

The agent has 18 files on the Desktop that belong to three personal projects, discoverable by filename prefix. The task tests whether an agent can:

1. Infer project membership from a consistent naming convention (HV_*, SC_*, GD_*)
2. Create a project folder hierarchy and move files into it
3. Lock every file using Finder's "Locked" flag (UF_IMMUTABLE)
4. Create a README.txt inside each project folder listing its contents
5. Leave the Desktop clean of project files

This is a realistic personal scenario: a user who has been dropping project files on the Desktop for months wants to organize them, lock them against accidental modification, and document what each folder contains.

## End State (Goal)

```
~/Documents/Projects/
├── Home Renovation/
│   ├── HV_kitchen_quotes.txt       [locked]
│   ├── HV_bathroom_tiles.txt       [locked]
│   ├── HV_paint_colors.txt         [locked]
│   ├── HV_permit_checklist.txt     [locked]
│   ├── HV_before_photos.txt        [locked]
│   ├── HV_timeline.txt             [locked]
│   └── README.txt                  (lists the 6 HV_ filenames)
├── School Schedule/
│   ├── SC_fall_schedule.txt        [locked]
│   ├── SC_teacher_contacts.txt     [locked]
│   ├── SC_activities.txt           [locked]
│   ├── SC_homework_tracker.txt     [locked]
│   ├── SC_supply_list.txt          [locked]
│   ├── SC_holidays.txt             [locked]
│   └── README.txt                  (lists the 6 SC_ filenames)
└── Garden Design/
    ├── GD_zone_map.txt             [locked]
    ├── GD_bed_layout.txt           [locked]
    ├── GD_seed_wishlist.txt        [locked]
    ├── GD_irrigation.txt           [locked]
    ├── GD_composting.txt           [locked]
    ├── GD_pest_log.txt             [locked]
    └── README.txt                  (lists the 6 GD_ filenames)

Desktop: no HV_, SC_, or GD_ files remain.
```

## File → Project Map

| Prefix | Project Folder |
|--------|---------------|
| HV_ | Home Renovation |
| SC_ | School Schedule |
| GD_ | Garden Design |

6 files per project × 3 projects = 18 files total.

## Success Criteria

| Criterion | Points | Details |
|-----------|--------|---------|
| C1: Files in correct project subfolder | 40 | proportional (18 files) |
| C2: Every moved file is locked | 25 | proportional (18 files) |
| C3: README.txt in each folder with ≥3 filenames | 20 | 7+7+6 pts |
| C4: Desktop has no remaining HV_/SC_/GD_ files | 15 | binary |
| **Total** | **100** | Pass at ≥75 |

## Verification Strategy

`export_result.sh` reads:
- `files_by_folder` — `os.listdir` per project subfolder (excluding README.txt)
- `locked_by_file` — `os.stat(path).st_flags & 0x00020000 != 0` per file
- `readme_by_folder` — raw text of README.txt per subfolder (None if missing)
- `desktop_leftover` — `os.listdir(~/Desktop)` filtered to HV_/SC_/GD_ prefixes

Verifier checks placement, lock status (UF_IMMUTABLE flag), README content (filename mentions), and Desktop cleanliness.

## Edge Cases and Potential Issues

- File locking in Finder: right-click → Get Info (⌘I) → check "Locked" checkbox. This sets the UF_IMMUTABLE flag (0x00020000 in st_flags).
- The README.txt inside each project folder is NOT checked for lock status — only the 18 moved project files are.
- Desktop leftover check uses prefix matching, so any HV_/SC_/GD_ file anywhere on the Desktop (even in a subfolder) would be caught by the find-based logic in export_result.sh.
- README.txt content only needs to reference ≥3 filenames (checked by substring match) — format is flexible.
- Pass threshold is 75 (higher than other tasks) because wrong-folder placement has a severe score penalty.
