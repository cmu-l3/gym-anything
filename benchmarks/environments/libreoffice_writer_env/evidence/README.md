# LibreOffice Writer Environment - Test Evidence

## Environment Boot Test (No Task)

**Screenshot**: `env_boot_no_task.png`

Ubuntu GNOME desktop with LibreOffice Writer desktop shortcut visible. Environment boots cleanly.

### Pre-start log output (installation):
```
=== Installing LibreOffice Writer and related packages ===
...
Setting up fonts-noto (20201225-1build1) ...
=== LibreOffice Writer installation completed ===
```

### Post-start log output (configuration):
```
=== Setting up LibreOffice Writer configuration ===
Setting up LibreOffice Writer for user: ga
  - Created versionrc (7.3.7.2) to suppress What's New bar
  - Copied custom preferences
  - Created desktop shortcut
  - Created launch script
=== LibreOffice Writer configuration completed ===
```

### Installation verification:
```
LibreOffice: /usr/bin/libreoffice - version 7.3.7.2 30(Build:2)
python-docx: 1.2.0
xdotool: /usr/bin/xdotool
wmctrl: /usr/bin/wmctrl
```

---

## Task 1: Create Table of Contents

**Screenshot**: `task_create_table_of_contents_setup.png`

LibreOffice Writer open with Darwin's "On the Origin of Species" excerpt (38KB). All text in Normal style - agent must apply Heading 1/2 styles and insert TOC.

### Pre-task log:
```
=== Setting up Create Table of Contents Task ===
Created document with Darwin's Origin of Species excerpt
Launching LibreOffice Writer...
Process found after 1s
Window found after 5s
Window focused: 0x008000e8
=== Create Table of Contents Task Setup Complete ===
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 20,
  "feedback": "Chapter headings: only 0/4 have Heading 1 style | Section headings: only 0/8 have Heading 2 style | Table of Contents NOT detected | Content preserved: 4/4 key phrases | TOC not found near beginning of document | VLM: unavailable (skipped)"
}
```
*Note: Only content preservation (criterion 4) passes at baseline. Criterion 5 changed from heading count to TOC placement check after audit.*

---

## Task 2: Mail Merge Form Letter

**Screenshot**: `task_mail_merge_form_letter_setup.png`

LibreOffice Writer open with library renewal template. Template shows Greenfield Public Library letterhead with {Name}, {Address}, {City}, {State} placeholders. CSV file with 5 patrons created at /home/ga/Documents/patrons.csv.

### Pre-task log:
```
=== Setting up Mail Merge Form Letter Task ===
Created letter template and patron CSV data
Launching LibreOffice Writer...
Process found after 1s
Window found after 5s
Window focused: 0x022000e8
=== Mail Merge Form Letter Task Setup Complete ===
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 20,
  "feedback": "Merged output file NOT found (fell back to template) | Patron names missing: only 0/5 found | Letter structure: 4/4 phrases found | Page breaks insufficient: 0 (expected >= 4) | Raw placeholders still present: 6 | VLM: unavailable (skipped)"
}
```

---

## Task 3: Format Research Paper

**Screenshot**: `task_format_research_paper_setup.png`

LibreOffice Writer open with unformatted climate science paper (39KB). Contains title, authors, abstract, 7 sections, 4 subsections, and 10 references in raw text format.

### Pre-task log:
```
=== Setting up Format Research Paper Task ===
Created document with real climate science research paper content
Launching LibreOffice Writer...
Process found after 1s
Window found after 6s
Window focused: 0x008000e8
=== Format Research Paper Task Setup Complete ===
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 14,
  "feedback": "Title: not formatted correctly | Authors: not formatted correctly | Section headings: only 0/7 have Heading 1 | Subsection headings: only 0/4 have Heading 2 | Body text not justified: only 0/4 | Hanging indent: only 0/10 references | Content preserved: 4/4 | VLM: unavailable (skipped)"
}
```

---

## Task 4: Bibliography Formatting

**Screenshot**: `task_bibliography_formatting_setup.png`

LibreOffice Writer open with 10 psychology citations in mixed/wrong formats (MLA, Chicago, informal). All citations from real published papers (Kahneman, Bandura, Milgram, etc.).

### Pre-task log:
```
=== Setting up Bibliography Formatting Task ===
Created document with 10 messy citations from real psychology publications
Launching LibreOffice Writer...
Process found after 1s
Window found after 6s
Window focused: 0x006000e8
=== Bibliography Formatting Task Setup Complete ===
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "'References' heading: NOT found | APA format issues: only 1/10 follow APA style | NOT alphabetically ordered: Kahneman -> Social -> Stanley -> Skinner -> The | Hanging indent: only 0/10 entries | Italics missing: only 0/10 entries | VLM: unavailable (skipped)"
}
```
*Note: Score changed from 20 to 0 after audit fix. Old criterion 2 checked author name presence (always passed). New criterion 2 validates actual APA formatting (correctly fails at baseline since citations are in wrong formats).*

---

---

## Task 5: NIH R01 Grant Compliance Reformatting

**Screenshot**: `nih_grant_compliance_setup.png`
**Occupation**: Grants Administrator / Life Scientist | **Industry**: Biomedical Research
**Difficulty**: very_hard

LibreOffice Writer open with `r01_draft.docx` — a 3-page R01 draft for "Modulating Tumor-Infiltrating Macrophage Polarization States" (40KB). Document uses Liberation Serif 10pt font, 1-inch margins, no heading styles, no header, no hanging indent in references.

### Pre-task log:
```
=== NIH Grant Compliance Task Setup Complete ===
Source document: /home/ga/Documents/r01_draft.docx
Required output: /home/ga/Documents/r01_formatted.docx
```

### Setup verification:
```
setup_files: /tmp/task_start_screenshot.png (248KB), /tmp/task_start_timestamp
documents: /home/ga/Documents/r01_draft.docx (40KB)
libreoffice_running: 7932 /usr/lib/libreoffice/program/soffice.bin --writer --norestore /home/ga/Documents/r01_draft.docx
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "Output file r01_formatted.docx not found or unreadable: Failed to copy file: Source not found: /home/ga/Documents/r01_formatted.docx"
}
```
*Do-nothing test correctly returns score=0 (output file not created).*

---

## Task 6: Professional Services Agreement Finalization

**Screenshot**: `legal_psa_finalization_setup.png`
**Occupation**: Corporate Attorney | **Industry**: Legal Services
**Difficulty**: very_hard

LibreOffice Writer open with `psa_draft.docx` — a 9-section PSA between Vertex Analytics Corp. and Meridian Data Solutions LLC (40KB). Title is 11pt unformatted, section headings are plain text, defined terms not bolded, signature block is plain text, no footer.

### Pre-task log:
```
=== Legal PSA Finalization Task Setup Complete ===
Source document: /home/ga/Documents/psa_draft.docx
Required output: /home/ga/Documents/psa_final.docx
```

### Setup verification:
```
setup_files: /tmp/task_start_screenshot.png (213KB), /tmp/task_start_timestamp
documents: /home/ga/Documents/psa_draft.docx (40KB)
libreoffice_running: 7928 /usr/lib/libreoffice/program/soffice.bin --writer --norestore /home/ga/Documents/psa_draft.docx
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "Output file psa_final.docx not found or unreadable: Failed to copy file: Source not found: /home/ga/Documents/psa_final.docx"
}
```

---

## Task 7: Internal Audit Report Formatting

**Screenshot**: `audit_report_formatting_setup.png`
**Occupation**: Internal Auditor (CAE) | **Industry**: Financial Services
**Difficulty**: very_hard

LibreOffice Writer open with `audit_draft.docx` — a Q3 2024 internal audit report for NorthBridge Financial Group with 5 findings (40KB). Executive Summary is plain text, finding headings are plain bold, risk table has no shading or colored text, no footer.

### Pre-task log:
```
=== Audit Report Formatting Task Setup Complete ===
Source: /home/ga/Documents/audit_draft.docx
Required output: /home/ga/Documents/audit_final.docx
```

### Setup verification:
```
setup_files: /tmp/task_start_screenshot.png (209KB), /tmp/task_start_timestamp
documents: /home/ga/Documents/audit_draft.docx (40KB)
libreoffice_running: 7936 /usr/lib/libreoffice/program/soffice.bin --writer --norestore /home/ga/Documents/audit_draft.docx
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "Output file audit_final.docx not found or unreadable: Failed to copy file: Source not found: /home/ga/Documents/audit_final.docx"
}
```

---

## Task 8: Clinical Trial Protocol Safety Amendment

**Screenshot**: `clinical_protocol_amendment_setup.png`
**Occupation**: Medical Writer / Regulatory Affairs | **Industry**: Pharmaceutical Research
**Difficulty**: very_hard

LibreOffice Writer open with `protocol_v1.docx` — a Phase II clinical trial protocol for HELI-CARD-201 (42KB). Version 1.0 dated 14 January 2024. Requires amendment to add QTc exclusion criterion, tighten stopping rule, add Section 9.4, and update version history.

### Pre-task log:
```
=== Clinical Protocol Amendment Task Setup Complete ===
Source: /home/ga/Documents/protocol_v1.docx
Required output: /home/ga/Documents/protocol_v2.docx
```

### Setup verification:
```
setup_files: /tmp/task_start_screenshot.png (222KB), /tmp/task_start_timestamp
documents: /home/ga/Documents/protocol_v1.docx (42KB)
libreoffice_running: 7939 /usr/lib/libreoffice/program/soffice.bin --writer --norestore /home/ga/Documents/protocol_v1.docx
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "Output file protocol_v2.docx not found or unreadable: Failed to copy file: Source not found: /home/ga/Documents/protocol_v2.docx"
}
```

---

## Task 9: Structural Engineering Inspection Report Formatting

**Screenshot**: `engineering_inspection_report_setup.png`
**Occupation**: Licensed Structural Engineer (PE) | **Industry**: Architecture and Engineering
**Difficulty**: very_hard

LibreOffice Writer open with `inspection_draft.docx` — a structural inspection report for Riverside Office Complex by PE Michael T. Caldwell (License TX-78234, 41KB). Contains 7 observations as plain paragraphs, 3 calculation blocks as plain text, 5 figure captions, and PE certification as plain text.

### Pre-task log:
```
=== Engineering Inspection Report Task Setup Complete ===
Source: /home/ga/Documents/inspection_draft.docx
Required output: /home/ga/Documents/inspection_report.docx
```

### Setup verification:
```
setup_files: /tmp/task_start_screenshot.png (205KB), /tmp/task_start_timestamp
documents: /home/ga/Documents/inspection_draft.docx (41KB)
libreoffice_running: 7930 /usr/lib/libreoffice/program/soffice.bin --writer --norestore /home/ga/Documents/inspection_draft.docx
```

### Baseline verification result:
```json
{
  "passed": false,
  "score": 0,
  "feedback": "Output file inspection_report.docx not found or unreadable: Failed to copy file: Source not found: /home/ga/Documents/inspection_report.docx"
}
```

---

## Verification Checklist

- [x] Installation script completes without errors
- [x] Setup script completes without errors
- [x] LibreOffice Writer visible in screenshot
- [x] All documents created correctly (python-docx in VM)
- [x] All 4 original task setups run without errors
- [x] All 5 new task setups run without errors (Tasks 5-9)
- [x] Export scripts produce valid output
- [x] All 4 original verifiers can read and process documents
- [x] All 5 new verifiers: do-nothing baseline correctly returns score=0
- [x] All baselines correctly fail (no false positives)
- [x] Content preservation checks pass for all tasks
- [x] python-docx installed on both host (1.2.0) and VM (1.2.0)
- [x] xdotool/wmctrl functional for window management
- [x] DISPLAY=:1 environment properly configured
- [x] ImageMagick `import` used for screenshots (scrot not in root PATH)
