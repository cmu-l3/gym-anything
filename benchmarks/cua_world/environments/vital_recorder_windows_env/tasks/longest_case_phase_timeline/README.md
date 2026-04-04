# Task: longest_case_phase_timeline

## Domain Context

Perioperative time management is a key area of surgical quality improvement. Understanding how time is allocated across preoperative preparation, surgery, and emergence provides insight into workflow efficiency and patient throughput. Anesthesiologists and perioperative researchers routinely analyze case timelines from intraoperative data management systems.

Vital Recorder captures event markers (Case started, Surgery started, Surgery finished, Case finished) automatically from the anesthesia workstation, enabling precise phase-duration computation.

## Occupation Context

**Primary users**: Anesthesia Researchers, Quality Improvement Officers, Perioperative Medicine Specialists
**Task type**: Comparative case analysis — temporal decomposition of the longest surgical case

## Task Goal

The agent must:
1. Compare all three recordings to identify the longest one (case 0002, ~4h 22min)
2. Navigate the event timeline in VitalRecorder for that case
3. Export only the intraoperative segment (not the full recording)
4. Write a structured phase analysis report with actual durations and percentages

## Why This Is Hard

- The agent must open multiple files to compare durations
- The agent must read event timestamps from the VitalRecorder interface
- The agent must perform arithmetic (compute phase durations, percentages)
- The export requires navigating to the correct segment rather than exporting the full file
- The report requires structured quantitative content, not vague descriptions

## Ground Truth

- **Longest case**: 0002.vital (~4h 22min = ~262 minutes total)
  - Tracks: ECG_II, PLETH, HR, ST_II, ST_V5, NIBP_SYS/DIA/MEAN, SpO2, VENT_TV, VENT_PEEP, VENT_RR
  - Events: Case started → Surgery started → Surgery finished → Case finished
- **Shorter cases**: 0001 (~3h 12min), 0003 (~1h 13min)
- **Expected CSV**: `C:\Users\Docker\Desktop\longest_case_intraop.csv` — intraoperative segment only
- **Expected report**: `C:\Users\Docker\Desktop\phase_analysis.txt` — phase durations and percentages

## Success Criteria

| Criterion | Points | What Is Checked |
|-----------|--------|-----------------|
| Intraop CSV exists with cardiovascular columns from case 0002 | 25 | File ≥100 bytes, header has HR/NIBP/SpO2/VENT |
| CSV is an intraop segment (row count < full case) | 20 | Row count < 14,000 rows (not full 15,740) |
| Phase report exists with substantial content | 20 | File ≥400 bytes |
| Report identifies case 0002 as the longest case | 20 | "0002" in text with duration/longest context |
| Report has quantitative phase-duration data | 15 | Numeric values with minute/percentage terms |

**Pass threshold**: 60/100
**Output gate**: Score=0 if neither CSV nor report exists

## Verification Strategy

- CSV header is scanned for HR, NIBP, SpO2, VENT terms (unique to case 0002)
- CSV row count is checked to confirm it represents a segment, not the full recording
- Report text is checked for case identifier, numeric values, phase terminology
- Both files are independently retrieved from VM via copy_from_env
