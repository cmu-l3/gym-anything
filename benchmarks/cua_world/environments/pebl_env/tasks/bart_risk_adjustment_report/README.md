# BART Risk Adjustment Report

## Task Overview

**Domain**: Behavioral Economics / Addiction Research — Risk-Taking Assessment
**Difficulty**: Very Hard
**Occupation**: Clinical Psychologist, Behavioral Economist, Addiction Researcher

A research team has collected Balloon Analogue Risk Task (BART) data from 11 participants (from the CNP OpenNeuro ds000030 dataset). One additional participant (sub-99999) has been injected with impossible data (pumps=0 on all trials), simulating a data recording failure. The dataset is at `~/pebl/data/bart_data.csv`.

## Goal

Compute ADJMEANPUMPS for each valid participant and produce a JSON report at `~/pebl/analysis/bart_report.json`.

## Data Format

`bart_data.csv` columns:
- `participant_id`: participant ID (e.g., sub-10159)
- `trial`: trial number
- `pumps`: number of balloon pumps before stopping
- `exploded`: 1 if balloon exploded, 0 if participant cashed out

## ADJMEANPUMPS Definition

ADJMEANPUMPS = mean(pumps) for all trials where exploded=0 (non-explosion trials only). This is the standard behavioral measure of risk-taking in the BART.

## Output Format

```json
{
  "participants": [
    {"id": "sub-10159", "adjmeanpumps": 3.15},
    {"id": "sub-99999", "excluded": true, "reason": "pumps=0 on all trials"}
  ],
  "group_adjmeanpumps": 4.39
}
```

## Verification Criteria

1. **Output file exists and is valid JSON** (10 pts)
2. **sub-99999 correctly excluded** (25 pts)
3. **ADJMEANPUMPS within ±0.5 for ≥8 of 11 valid participants** (35 pts)
4. **Group mean ADJMEANPUMPS within ±0.3 of ground truth (4.3897)** (30 pts)

Pass threshold: 60 pts

## Data Source

Real CNP OpenNeuro ds000030 BART data (11 participants).
Citation: Gorgolewski, K.J., et al. (2017). A high-resolution 7-Tesla resting-state fMRI test-retest dataset with cognitive and physiological measures. *Scientific Data*, 4, 170036. doi:10.1038/sdata.2017.93

sub-99999 is injected by setup_task.sh with pumps=0 on all trials (impossible BART data pattern).
