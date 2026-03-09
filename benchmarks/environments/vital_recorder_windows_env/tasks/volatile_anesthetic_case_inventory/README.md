# Task: volatile_anesthetic_case_inventory

## Domain Context

Volatile anesthetic agents like sevoflurane are administered by inhalation during general anesthesia. Monitoring both inspired (INSP_SEVO) and expired (EXP_SEVO) concentrations allows anesthesiologists to assess the agent's washout, estimate the alveolar concentration (which correlates with anesthetic depth), and calculate the MAC (Minimum Alveolar Concentration) fraction. Pharmacy departments and quality committees track anesthetic agent usage for consumption audits, drug purchasing, and cost analysis.

Vital Recorder captures anesthetic agent concentrations directly from vaporizer telemetry and gas analyzer outputs when connected to compatible anesthesia workstations (e.g., Primus, Perseus, Julian series).

## Occupation Context

**Primary users**: Anesthesiologists, Pharmacy & Therapeutics Committee Members, Anesthesia Quality Coordinators
**Task type**: Cross-case monitoring inventory — identifying which cases have anesthetic agent data

## Task Goal

The agent must:
1. Open all three .vital files and examine their track lists
2. Identify which cases have INSP_SEVO and EXP_SEVO tracks (cases 0001 and 0003)
3. Export both sevo-containing cases to CSVs
4. Write a comprehensive inventory report

## Why This Is Hard

- Agent is NOT told which cases have sevoflurane data — must discover by inspection
- Two out of three files have sevo data; agent must correctly identify BOTH
- Agent must export two separate CSV files (not one)
- Case 0002 has a cardiovascular monitoring profile but NO anesthetic agent data
- Report must contain clinically meaningful content about why both concentrations matter
- The agent must correctly exclude case 0002 from the export

## Ground Truth

- **Cases with INSP_SEVO + EXP_SEVO**: 0001.vital, 0003.vital
- **Case without sevo**: 0002.vital (has ECG, PLETH, HR, NIBP, SpO2, VENT — cardiovascular only)
- **Expected CSVs**: `case_0001_sevo.csv` and `case_0003_sevo.csv` on Desktop
- **Expected report**: `anesthetic_inventory.txt` on Desktop

## Success Criteria

| Criterion | Points | What Is Checked |
|-----------|--------|-----------------|
| CSV for case 0001 with SEVO columns exists | 25 | File ≥100 bytes, INSP_SEVO/EXP_SEVO in header |
| CSV for case 0003 with SEVO columns exists | 25 | File ≥100 bytes, INSP_SEVO/EXP_SEVO in header |
| Inventory report exists with substantial content | 20 | File ≥400 bytes |
| Report notes case 0002 as lacking sevoflurane data | 15 | "0002" in report with exclusion/no-sevo language |
| Report contains clinical content about anesthetic monitoring | 15 | Sevo/MAC/alveolar/anesthetic terminology |

**Pass threshold**: 60/100
**Output gate**: Score=0 if no output files at all exist

## Verification Strategy

- Both CSV files are independently retrieved and their headers scanned for SEVO/INSP/EXP keywords
- Report text is checked for case identifiers and sevoflurane/anesthetic terminology
- The excluded case (0002) must be mentioned with exclusion language in the report
- File sizes ensure content is substantive
