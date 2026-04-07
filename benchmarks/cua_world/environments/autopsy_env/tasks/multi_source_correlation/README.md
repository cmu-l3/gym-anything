# Task: multi_source_correlation

**Difficulty**: very_hard
**Environment**: autopsy_env
**Occupation Context**: Detectives and Criminal Investigators — digital evidence analysis

## Overview

Intelligence suggests a suspect copied files between two devices — a USB drive and a camera storage card. Both device images have been seized. The investigator must perform cross-device analysis to determine whether any files were duplicated, corroborating the intelligence.

## Expected Agent Actions

1. Create forensic case `Cross_Device_Analysis_2024` (case number `INV-COR-005`)
2. Add **both** `/home/ga/evidence/ntfs_undel.dd` AND `/home/ga/evidence/jpeg_search.dd` as separate Disk Image data sources to the SAME case; enable **Hash Lookup** and **File Type Identification**
3. After ingest, compare files across both data sources using MD5 hashes
4. Write `/home/ga/Reports/correlation_report.txt` with:
   - `SOURCE_1_FILES: N`
   - `SOURCE_2_FILES: N`
   - `CROSS_DEVICE_MATCHES: N`
   - One line per match: `MATCH: <md5> | <name_src1> | <name_src2>`
5. Write `/home/ga/Reports/correlation_summary.txt` with:
   - `UNIQUE_FILES_SOURCE1: N`
   - `UNIQUE_FILES_SOURCE2: N`
   - `SHARED_FILES: N`
   - `INVESTIGATION_CONCLUSION: <assessment>`

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Case DB found | 10 |
| Both disk images added as data sources | 20 |
| Ingest completed on both sources | 15 |
| Correlation report exists, recent, has required sections | 20 |
| File counts in report within tolerance of GT | 20 |
| Summary with investigation conclusion section | 15 |

## Ground Truth

Pre-computed using `icat` to extract and MD5-hash all files from both images. Stored in `/tmp/multi_source_gt.json`. Cross-device matches identified by matching MD5 hashes across both images.
