# Upload Clinical Source Documents (`upload_clinical_source_documents@1`)

## Overview
This task evaluates the agent's ability to perform file-based data entry in an Electronic Data Capture (EDC) system. The agent must locate specific subject events, open the targeted Case Report Forms (CRFs), and upload local file attachments representing anonymized source documents (e.g., ECG tracings and lab reports) via the web interface.

## Rationale
**Why this task is valuable:**
- **Tests Complex UI Interaction:** Evaluates the agent's ability to interact with file upload widgets (`<input type="file">`) within a multi-step web application workflow, which VLMs often struggle with compared to standard text inputs.
- **Cross-Domain Path Mapping:** Requires mapping local filesystem paths to specific browser-based data entry fields accurately across multiple subjects.
- **Workflow Authenticity:** Exercises standard clinical trial workflows where centralized medical review requires uploading anonymized source documents to the EDC.
- **File-State Verification:** Differentiates from standard text data entry tasks by verifying binary file blob storage and database path linking.

**Real-world Context:** Clinical Research Coordinators (SOC Major Group: Management) frequently upload anonymized source documents into Case Report Forms (CRFs). In this scenario, the central monitoring team requires the Baseline ECG tracing for subject DM-101 and the Screening Lab Report for subject DM-102 to verify patient eligibility. The coordinator must upload these documents into the EDC immediately to prevent a delay in the trial's treatment assignment phase.

## Task Description

**Goal:** Upload two anonymized source document PDFs to the "Central Review Uploads" CRF for subjects DM-101 and DM-102 in the Phase II Diabetes Trial.

**Starting State:** 
- OpenClinica is running in Firefox, logged in as `root` (Admin123!).
- The active study is "Phase II Diabetes Trial" (`DM-TRIAL-2024`).
- Two realistic source documents are located on the filesystem:
  - `/home/ga/source_docs/DM-101_ECG.pdf`
  - `/home/ga/source_docs/DM-102_LabReport.pdf`
- Both subjects have a scheduled "Baseline Assessment" event that includes a CRF named "Central Review Uploads".

**Expected Actions:**
1. Navigate to the Subject Matrix for the study.
2. Locate subject **DM-101**.
3. Open their "Baseline Assessment" event and start data entry for the **Central Review Uploads** CRF.
4. Fill out the CRF as follows:
   - **Document Type**: Select "ECG" from the dropdown
   - **File Attachment**: Upload `/home/ga/source_docs/DM-101_ECG.pdf`
   - **Comments**: Enter "Baseline ECG"
5. Save the CRF and mark it as **Complete**.
6. Locate subject **DM-102**.
7. Open their "Baseline Assessment" event and start data entry for the **Central Review Uploads** CRF.
8. Fill out the CRF as follows:
   - **Document Type**: Select "Lab Report" from the dropdown
   - **File Attachment**: Upload `/home/ga/source_docs/DM-102_LabReport.pdf`
   - **Comments**: Enter "Screening Labs"
9. Save the CRF and mark it as **Complete**.

**Final State:**
Both CRFs are marked as complete. The OpenClinica database contains records of the uploaded files in the `item_data` table, the document types and comments are saved accurately, and the physical PDF files are stored in the Tomcat `attached_files` directory.

## Verification Strategy

### Primary Verification: Database & Filesystem Hybrid Check
The verifier script (`verifier.py`) checks both the PostgreSQL database and the OpenClinica container's filesystem:
1. **Database `item_data` Check:** Queries the `item_data` table for the specific items linked to the "Central Review Uploads" CRF for both subjects. For FILE item types, OpenClinica stores the modified filename/relative path. The verifier checks that the value column contains the substring `DM-101_ECG.pdf` for subject 1, and `DM-102_LabReport.pdf` for subject 2.
2. **Metadata Checks:** Queries the `item_data` table to verify the "Document Type" and "Comments" text values match the exact requested strings.
3. **CRF Status:** Queries the `event_crf` table to ensure `status_id = 4` (Completed) for both subject events.

### Secondary Verification: Container Filesystem Check
The export script (`export_result.sh`) will run a `docker exec` command to `ls` the `/usr/local/tomcat/openclinica_data/attached_files/` directory and ensure the physical binary blobs of the PDF files were successfully written by the application layer.

### Anti-Gaming Verification
- **Audit Log Inspection:** The verifier compares the audit event count before and after the task. If no UI-driven web requests are recorded (i.e., the agent attempted to use `docker exec` to directly insert SQL rows and move files), the task scores zero.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| DM-101 File Upload | 25 | `item_data` contains reference to `DM-101_ECG.pdf` for DM-101's Baseline CRF, and the file exists in the Tomcat attachment directory. |
| DM-102 File Upload | 25 | `item_data` contains reference to `DM-102_LabReport.pdf` for DM-102's Baseline CRF, and the file exists in the Tomcat attachment directory. |
| CRF Completion Status | 20 | Both `event_crf` records are marked with `status_id = 4` (Completed). (10 pts per subject) |
| Metadata Accuracy | 15 | "Document Type" dropdown values were correctly selected for both subjects. |
| Comment Accuracy | 15 | "Comments" text inputs exactly match "Baseline ECG" and "Screening Labs". |
| Audit Trail Absence | -100 | PENALTY: Applied if no new web-application audit logs are present. |
| **Total** | **100** | |

**Pass Threshold:** 70 points with at least one file successfully uploaded and linked.