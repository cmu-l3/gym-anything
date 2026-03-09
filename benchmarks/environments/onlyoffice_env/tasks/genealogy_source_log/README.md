# Genealogy Source Log Task (`genealogy_source_log@1`)

## Overview

This task tests an agent's ability to create a properly formatted genealogy research source log using OnlyOffice Writer. The agent must create a structured document that catalogs research sources with proper citations, notes about findings, and organized formatting following genealogical documentation standards. This represents an essential skill for serious family history research where proper source attribution is as important as in academic work.

## Rationale

**Why this task is valuable:**
- **Research Documentation Standards:** Introduces proper citation formatting for historical records
- **Structured Information Organization:** Tests ability to combine tables, formatted text, and hierarchical sections
- **Real-World Research Skills:** Mirrors actual genealogy workflow where tracking sources prevents duplicate work
- **Mixed Data Handling:** Combines structured data (dates, names, repositories) with narrative notes
- **Professional Practice:** Teaches documentation habits essential for serious genealogical research
- **Citation Formatting:** Introduces academic-style citation conventions in a practical context

**Real-world scenario:** A genealogist has consulted multiple sources (census records, birth certificates, online databases, family documents) over several research sessions. They need to create a source log to track what they've examined, where to find each source again, and what information each source provided. Without this documentation, they risk re-checking the same sources or losing track of important findings.

## Task Requirements

### Must Create:
1. **Document Title:** "Genealogy Research Source Log" with context subtitle
2. **Table Structure:** 4 columns (Source ID, Citation, Repository/Location, Notes)
3. **Source Entries:** At least 3 diverse citations representing different source types
4. **Proper Formatting:** Italic text for publication/collection titles (genealogical standard)
5. **Research Notes:** Section with next steps or research questions
6. **File Location:** `/home/ga/Documents/TextDocuments/genealogy_source_log.docx`

### Example Source Types:
- Census records (e.g., 1940 U.S. Federal Census)
- Vital records (birth/death/marriage certificates)
- Online databases (FamilySearch, Ancestry, etc.)
- Archival documents
- Newspapers/obituaries

## Verification Criteria

The verifier checks for:

1. **Document Validity** (10 pts): File exists and is valid DOCX
2. **Title Presence** (10 pts): Contains "Genealogy" and "Source Log"
3. **Table Columns** (10 pts): At least 4 columns present
4. **Data Rows** (10 pts): At least 3 source entries
5. **Table Headers** (10 pts): Appropriate column labels
6. **Date Information** (10 pts): Citations include dates
7. **Location Information** (10 pts): Citations include geographic locations
8. **Repository Information** (10 pts): Where records are held
9. **Italic Formatting** (10 pts): Publication titles properly italicized
10. **Research Notes** (10 pts): Section with next steps

**Pass Threshold:** 70/100 points

## Files

- `task.json` - Task configuration
- `setup_genealogy_task.sh` - Launches OnlyOffice Writer
- `export_genealogy_log.sh` - Saves and exports document
- `verifier.py` - Validates document structure and content
- `README.md` - This file

## Example Citation Format
