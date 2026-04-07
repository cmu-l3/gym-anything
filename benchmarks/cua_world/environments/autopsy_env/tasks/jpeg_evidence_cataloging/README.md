# Task: jpeg_evidence_cataloging

**Difficulty**: very_hard
**Environment**: autopsy_env
**Occupation Context**: Detectives and Criminal Investigators — digital evidence analysis

## Overview

A forensic examiner is working a case involving image-based evidence on a suspect's device. The disk image `jpeg_search.dd` contains JPEG photographs, including files embedded in unallocated space. The examiner must produce a complete, structured catalog of all JPEG files found.

## Expected Agent Actions

1. Create forensic case `JPEG_Catalog_2024` (case number `INV-JPEG-002`)
2. Add `/home/ga/evidence/jpeg_search.dd` as a Disk Image data source; enable **File Type Identification**, **Picture Analyzer**, and **Hash Lookup** modules
3. After ingest, navigate to File Views > Images to see all JPEGs including carved ones
4. Write catalog to `/home/ga/Reports/jpeg_catalog.tsv` (tab-delimited, with header):
   - `FILENAME\tFULL_PATH\tSIZE_BYTES\tMD5_HASH\tALLOCATED`
5. Write summary to `/home/ga/Reports/jpeg_catalog_summary.txt`:
   - `TOTAL_JPEG_FILES: N`, `ALLOCATED_FILES: N`, `CARVED_UNALLOCATED: N`

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Case DB found | 15 |
| Disk image data source added | 15 |
| Ingest completed with MIME-type identification | 10 |
| JPEG count in DB matches TSK ground truth | 20 |
| Catalog TSV has correct format and is recent | 20 |
| Catalog covers ≥50% of GT JPEG file names | 20 |

## Ground Truth

Pre-computed using `fls -r /home/ga/evidence/jpeg_search.dd`, filtering for `.jpg`/`.jpeg` extensions. Stored in `/tmp/jpeg_evidence_gt.json`.

## Disk Image

DFTT Test #8 "JPEG Search" — FAT filesystem image containing JPEG photographs including files in unallocated space that require carving to find. Source: Digital Forensics Tool Testing (DFTT) project.
