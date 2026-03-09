# Task: arterial_pressure_case_audit

## Domain Context

Invasive arterial blood pressure monitoring (A-line) is a standard of care in high-risk noncardiac surgeries and provides continuous beat-to-beat hemodynamic data not available from non-invasive devices. Anesthesia quality departments conduct retrospective audits of case recordings to identify which patients had arterial lines and whether hemodynamic targets (e.g., MAP ≥65 mmHg) were maintained.

Vital Recorder (VitalDB, Seoul National University Hospital) captures intraoperative physiological data from anesthesia workstations and monitors. The ART track specifically refers to invasive radial or femoral arterial pressure waveforms.

## Occupation Context

**Primary users**: Anesthesiologists, Anesthesia Quality Officers, Perioperative Researchers
**Task type**: Retrospective case audit — identifying monitoring completeness across a case set

## Task Goal

The agent must:
1. Open all three .vital recording files to inspect their track lists
2. Identify which case(s) contain an ART (invasive arterial) track
3. Export the ART-containing case's full data to CSV
4. Write a structured audit report documenting findings and clinical rationale

## Why This Is Hard

- The agent is NOT told which file contains ART — it must open each file and discover this
- 3 files must be examined; only 1 has ART (case 0001); the others have NIBP or no BP at all
- The agent must write a clinically substantive report, not just acknowledge file existence
- Multiple distinct actions: multi-file review, selective export, document creation

## Ground Truth

- **Case with ART**: 0001.vital (tracks: ART, ECG_II, ECG_V5, PLETH, CO2, AWP, INSP_SEVO, EXP_SEVO)
- **Cases without ART**: 0002.vital (has NIBP_SYS/DIA/MEAN, non-invasive), 0003.vital (no BP at all)
- **Expected CSV**: `C:\Users\Docker\Desktop\art_case_export.csv` — exported from 0001.vital
- **Expected report**: `C:\Users\Docker\Desktop\art_audit_report.txt`

## Success Criteria

| Criterion | Points | What Is Checked |
|-----------|--------|-----------------|
| CSV export exists with ART columns | 25 | File ≥100 bytes, header contains "ART" |
| Audit report exists with substantial content | 20 | File ≥300 bytes |
| Report correctly identifies case 0001 as having ART | 20 | "0001" mentioned alongside ART/arterial terms |
| Report notes excluded cases (0002/0003 lack ART) | 20 | "0002" or "0003" in report with exclusion language |
| Report contains clinical rationale | 15 | Hemodynamic/monitoring/management terms present |

**Pass threshold**: 60/100
**Output gate**: Score=0 if neither CSV nor report exists

## Verification Strategy

The verifier independently copies both output files from the VM and parses them:
- CSV header is scanned for "ART" substring
- Report text is scanned for case identifiers and clinical keywords
- File sizes ensure content is substantive, not stub files

## Potential Issues

- Agent might export case 0002 or 0003 instead — verifier checks for ART in CSV header
- Agent might skip one of the files — report content check catches this
- Agent might create report but not CSV — partial credit applies
