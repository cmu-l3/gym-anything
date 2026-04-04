# Task: respiratory_mechanics_lung_protection_review

## Domain Context

Lung-protective ventilation (LPV) is a ventilation strategy that uses low tidal volumes (~6 mL/kg IBW), appropriate PEEP, and limits plateau pressure to reduce ventilator-induced lung injury (VILI). Monitoring dynamic lung compliance and airway mechanics during surgery is essential for assessing whether LPV principles are being followed. Compliance (mL/cmH₂O) reflects lung and chest wall stiffness; MAWP (mean airway pressure) and PPLAT (plateau pressure) are key LPV targets.

Critical care consultants and perioperative anesthesiologists review intraoperative recordings to audit LPV adherence, particularly for high-risk patients.

## Occupation Context

**Primary users**: Critical Care Anesthesiologists, Pulmonary/Critical Care Physicians, Perioperative Quality Reviewers
**Task type**: Quality audit — identifying LPV-capable monitoring and reviewing mechanics during surgery only

## Task Goal

The agent must:
1. Open all three recordings to discover which has respiratory mechanics data
2. Identify case 0003 as the one with COMPLIANCE, MAWP_MBAR, PPLAT_MBAR
3. Navigate to the surgery events to extract only the intraoperative segment
4. Export ONLY the intraop segment (not full case) to CSV
5. Write a clinical ventilation review report

## Why This Is Hard

- Agent must inspect ALL three files to discover which has respiratory mechanics
- Cases 0001 and 0002 do NOT have lung compliance — only 0003 does
- Agent must export only the surgical segment (not the full 73-minute recording)
- Report requires domain-specific clinical judgment about LPV
- The agent must navigate the events panel, identify surgery timestamps, and use segment export

## Ground Truth

- **Case with respiratory mechanics**: 0003.vital
  - Tracks: COMPLIANCE, MAWP_MBAR, PPLAT_MBAR, PAMB_MBAR, ECG_II, ECG_V5, PLETH, INSP_SEVO, EXP_SEVO
  - Total duration: ~73 minutes (~4,394 seconds)
  - Intraoperative segment: determined by Surgery started/finished events in the recording
- **Cases without respiratory mechanics**: 0001.vital (has ART but no compliance), 0002.vital (has ventilator flow parameters but no COMPLIANCE)
- **Expected CSV**: `lung_protection_intraop.csv` — intraop segment of case 0003 only
- **Expected report**: `ventilation_review.txt`

## Success Criteria

| Criterion | Points | What Is Checked |
|-----------|--------|-----------------|
| CSV exists with respiratory mechanics columns | 25 | File ≥100 bytes, COMPLIANCE/MAWP/PPLAT in header |
| CSV is an intraop segment (not full recording) | 20 | Row count < 4,000 rows (full case ≈ 4,394 rows) |
| Ventilation report exists with substantial content | 20 | File ≥300 bytes |
| Report identifies case 0003 and its respiratory tracks | 20 | "0003" + compliance/MAWP/PPLAT/ventilat terms |
| Report contains clinical LPV assessment | 15 | Lung protection/compliance/tidal volume/PEEP terms |

**Pass threshold**: 60/100
**Output gate**: Score=0 if no output files at all exist
