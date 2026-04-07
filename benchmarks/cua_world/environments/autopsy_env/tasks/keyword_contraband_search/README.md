# Task: keyword_contraband_search

**Difficulty**: very_hard
**Environment**: autopsy_env
**Occupation Context**: Detectives and Criminal Investigators — digital evidence analysis

## Overview

A court order authorizes keyword searching of a suspect's USB drive (`ntfs_undel.dd`) for evidence of contraband trafficking. The investigator must configure Autopsy's keyword search ingest module, execute the search, and produce a documented report of all keyword hits.

## Expected Agent Actions

1. Create forensic case `Keyword_Search_2024` (case number `INV-KWD-004`)
2. Add `/home/ga/evidence/ntfs_undel.dd`; enable **Keyword Search** module only; add keywords: `secret`, `password`, `evidence`, `deleted`
3. After ingest, navigate to Results > Keyword Hits in left panel
4. Write `/home/ga/Reports/keyword_hits.txt` — one line per hit, pipe-delimited:
   - `KEYWORD|FILENAME|FILE_PATH|INODE|MATCH_CONTEXT`
5. Write `/home/ga/Reports/keyword_summary.txt` with:
   - `TOTAL_KEYWORDS_SEARCHED: 4`
   - `KEYWORDS_WITH_HITS: N`
   - `TOTAL_HIT_FILES: N`
   - One line per keyword: `KEYWORD <word>: N files`

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Case DB found | 15 |
| Disk image data source added | 15 |
| Ingest completed | 10 |
| Keyword hit artifacts in Autopsy DB | 20 |
| Hits report file exists, is recent, has pipe-delimited entries | 20 |
| Reports reference all 4 target keywords + summary has correct format | 20 |

## Ground Truth

Pre-computed using `icat` to extract file content and search for keywords, stored in `/tmp/keyword_contraband_gt.json`. The image content determines which keywords produce hits.
