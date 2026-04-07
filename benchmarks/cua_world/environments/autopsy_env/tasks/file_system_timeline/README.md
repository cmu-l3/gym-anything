# Task: file_system_timeline

**Difficulty**: very_hard
**Environment**: autopsy_env
**Occupation Context**: Detectives and Criminal Investigators — digital evidence analysis

## Overview

Investigators need to reconstruct the temporal sequence of activity on a suspect's USB drive. The file system timeline reveals when files were created, modified, accessed, and deleted — critical for establishing a sequence of events in a case.

## Expected Agent Actions

1. Create forensic case `Timeline_Analysis_2024` (case number `INV-TML-003`)
2. Add `/home/ga/evidence/ntfs_undel.dd`; enable **Recent Activity** ingest module only
3. After ingest, open Timeline Analyzer (Tools > Timeline), switch to File System events
4. Export timeline to `/home/ga/Reports/fs_timeline.csv` (pipe-delimited):
   - Header: `DATETIME|FILENAME|FULL_PATH|EVENT_TYPE|SIZE_BYTES`
5. Write narrative to `/home/ga/Reports/timeline_report.txt` with all 4 sections:
   - `DATE_RANGE: YYYY-MM-DD to YYYY-MM-DD`
   - `TOTAL_EVENTS: N`
   - `TOP_5_RECENT_FILES:` (5 lines with filename + timestamp)
   - `DELETION_EVIDENCE:` (describe deletions or "None found")

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Case DB found | 15 |
| Disk image data source added | 15 |
| Ingest completed | 10 |
| Timeline CSV exists, is recent, has pipe-delimited rows | 20 |
| CSV covers ≥50% of GT file names | 15 |
| Narrative report has all 4 required sections | 25 |

## Ground Truth

Pre-computed using `fls -r -l` + `istat` per file. Stored in `/tmp/file_system_timeline_gt.json`.
