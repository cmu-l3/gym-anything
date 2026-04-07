# Archival Subject Casebook Generation (`archival_casebook_generation@1`)

## Overview
This task evaluates the agent's ability to navigate an electronic data capture (EDC) system and utilize operating system integration (the browser's Print to PDF functionality) to generate a portable archival document of a subject's clinical record.

## Rationale
**Why this task is valuable:**
- **OS Integration / Browser Print:** Tests the agent's ability to break out of standard web navigation and interact with the OS/Browser print dialog to generate a file.
- **Hierarchical Navigation:** Tests spatial/UI reasoning to navigate the Study → Subject matrix to find specific records.
- **Real-world relevance:** Clinical Research Coordinators or Data Managers routinely generate PDF casebooks of individual subjects for safety reporting (SAE narratives), auditor requests, or investigator signatures.

**Real-world Context:** A regulatory auditor has requested the complete casebook for Subject CV-101 in the Cardiovascular Outcomes Registry. The Clinical Data Manager needs to generate a PDF of the subject's record to fulfill this request.

## Task Description

**Goal:** Generate a PDF casebook for Subject CV-101 in the Cardiovascular Outcomes Registry and save it to `/home/ga/Documents/CV-101_Casebook.pdf`.

**Starting State:**
- Firefox is open, maximized, logged into OpenClinica as `root`.
- Active study is `Cardiovascular Outcomes Registry` (CV-REG-2023).
- Subject `CV-101` is enrolled and visible in the Subject Matrix.

**Expected Actions:**
1. Navigate to the Subject Matrix.
2. Locate Subject `CV-101`.
3. Click the "View" (magnifying glass) icon for CV-101 to open their View Subject page.
4. Use the OpenClinica print feature or your browser's print functionality (Ctrl+P) to generate a PDF.
5. Save the printed PDF exactly to: `/home/ga/Documents/CV-101_Casebook.pdf`

**Final State:**
- A valid PDF file exists at the specified path containing the subject's details.

## Verification Strategy

### Primary Verification: File System & Content Parsing
The verifier checks for the existence of the PDF file and its size. It then uses `pdfminer` (or fallback tools) to parse the text layer of the PDF, verifying that the text contains the target subject ID ("CV-101") and study context keywords to prevent spoofing with empty or unrelated PDFs.

### Secondary Verification: File Modification Timestamps
Ensures the PDF was generated during the active task window by comparing the file's `mtime` with the task's start timestamp.

### Tertiary Verification: VLM Trajectory Check
A Vision Language Model analyzes frames from the agent's trajectory to confirm that the agent actually interacted with the OpenClinica interface and the browser print dialog, rather than simply writing text to a file via terminal commands.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| PDF Exists | 20 | The file is found at the specified or alternate path. |
| Time Constraint | 10 | The PDF was created after the task started. |
| Reasonable Size | 10 | The PDF is >5KB. |
| Content: Subject ID | 20 | Parsed text contains "CV-101". |
| Content: Study Context | 10 | Parsed text contains study keywords. |
| VLM Confirms Workflow | 30 | VLM confirms OpenClinica and Print dialog usage. |
| **Total** | **100** | |

**Pass Threshold:** 70 points