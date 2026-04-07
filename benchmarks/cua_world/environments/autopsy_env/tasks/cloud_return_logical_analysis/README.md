# Cloud Return Logical Evidence Analysis (`cloud_return_logical_analysis@1`)

## Overview
This task evaluates the agent's ability to process and analyze logical evidence files (such as cloud warrant returns or triage collections) in Autopsy, which requires a different data source workflow than traditional disk images. 

## Rationale
**Why this task is valuable:**
- Tests the "Logical Files" data source ingestion workflow in Autopsy.
- Evaluates the proper configuration of fundamental forensic processing modules (Hash Lookup, MIME Type Identification).
- Requires accurate aggregation and reporting of file metadata.
- **Real-world Context:** Modern forensic investigations frequently involve data returned from cloud providers (Google, Apple, Dropbox) or targeted triage acquisitions. These are provided as logical files and folders rather than sector-by-sector disk images.

## Task Description

**Goal:** Ingest a folder of logical cloud return files into an Autopsy case, run hash and MIME type identification, and generate a catalog and statistical summary of the contents.

**Starting State:** Autopsy is launched. A directory of logical files has been staged at `/home/ga/evidence/Cloud_Return/`. The `/home/ga/Reports/` directory is empty.

**Expected Actions:**
1. Create a new case `Cloud_Return_2024` (INV-CLD-001).
2. Add a **Logical Files** data source pointing to `/home/ga/evidence/Cloud_Return/`.
3. Enable only the **Hash Lookup** and **File Type Identification** ingest modules.
4. Export a tab-delimited catalog of all files to `/home/ga/Reports/logical_catalog.tsv` including filenames, paths, sizes, MD5 hashes, and MIME types.
5. Create a summary report at `/home/ga/Reports/cloud_summary.txt` indicating the total file count, JPEG count, and plain text file count.

**Final State:**
- The Autopsy case database is populated with the logical files.
- The TSV catalog exists and matches the database records.
- The TXT summary exists and its counts perfectly match Autopsy's MIME type categorization.

## Verification Strategy

### Primary Verification: SQLite Database and File Analysis
The verifier programmatically queries the `autopsy.db` SQLite database created by the agent to determine the absolute ground truth of what Autopsy processed (total files, jpeg count, text count). It then compares the agent's generated TSV catalog and TXT summary against this database state to ensure the agent correctly extracted the information from the UI.

### Anti-Gaming Measures
- Checks file modification timestamps (`mtime`) against the task start time to ensure reports weren't pre-staged.
- Validates the structural integrity of the TSV (header presence, tab delimiters).
- Ensures the data source added was actually logical (vs image).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Case Creation | 10 | Autopsy case DB found with correct name |
| Logical Source Added | 15 | Evidence directory successfully added as a data source |
| Ingest Completed | 15 | Files indexed in DB with MIME types and hashes |
| TSV Catalog | 30 | Tab-delimited file exists, is recent, and covers the indexed files |
| Summary Accuracy | 30 | Summary file counts accurately match Autopsy's internal DB counts |
| **Total** | **100** | |

Pass Threshold: 60 points with ingest completion and valid reporting.