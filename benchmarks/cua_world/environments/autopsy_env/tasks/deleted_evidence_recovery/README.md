# Task: deleted_evidence_recovery

**Difficulty**: very_hard
**Environment**: autopsy_env
**Occupation Context**: Detectives and Criminal Investigators — digital evidence analysis

## Overview

A USB drive image (`ntfs_undel.dd`) has been submitted as evidence in a data destruction case. The suspect is believed to have deleted incriminating files before surrendering the device. The investigator must use Autopsy to recover and document all deleted files.

## Expected Agent Actions

1. Create forensic case `Deleted_Evidence_2024` (case number `INV-DEL-001`)
2. Add `/home/ga/evidence/ntfs_undel.dd` as a Disk Image data source; enable **File Type Identification** ingest module only
3. After ingest, browse the file system tree to locate deleted files (red X badge / `$OrphanFiles`)
4. Export each deleted file to `/home/ga/Reports/deleted_evidence/`
5. Write forensic report to `/home/ga/Reports/deleted_evidence_report.txt`:
   - One line per file: `FILENAME|INODE_NUMBER|FILE_SIZE_BYTES|MD5_HASH`

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Case DB found for correct case name | 15 |
| Disk image data source added | 15 |
| Ingest completed | 10 |
| Deleted files in DB match TSK ground truth | 20 |
| Report file exists and is newer than task start | 15 |
| Report content covers ≥50% of GT deleted file names | 25 |

## Ground Truth

Pre-computed at setup time using `fls -r /home/ga/evidence/ntfs_undel.dd`, stored in `/tmp/deleted_evidence_gt.json`. The verifier compares report content against this ground truth.

## Disk Image

DFTT Test #7 "NTFS Undelete" — NTFS filesystem image containing allocated files and deleted files that can be recovered using standard forensic tools. Source: Digital Forensics Tool Testing (DFTT) project.
