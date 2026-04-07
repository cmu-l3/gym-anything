# Flanker Inhibitory Control Analysis

## Task Overview

**Domain**: Cognitive Neuroscience — Attention and Inhibitory Control
**Difficulty**: Very Hard
**Occupation**: Cognitive Neuroscientist, Research Psychologist

A cognitive neuroscience lab has collected Eriksen Flanker task data from 27 participants (s1–s27). One participant (s99) has been introduced into the dataset with impossibly fast reaction times (20–32 ms) simulating an equipment malfunction (stuck key or automated responder). The dataset is at `~/pebl/data/flanker_rt_data.csv`.

## Goal

Produce a JSON analysis report at `~/pebl/analysis/flanker_report.json`.

## Data Format

`flanker_rt_data.csv` columns:
- `participant`: participant ID (s1–s27 are real; s99 is contaminated)
- `block`: block number
- `trial`: trial number within block
- `flankers`: condition (congruent, incongruent, neutral)
- `rt`: reaction time in seconds

## Output Format

```json
{
  "participants": [
    {
      "id": "s1",
      "mean_rt_congruent_ms": 650.5,
      "mean_rt_incongruent_ms": 690.2,
      "mean_rt_neutral_ms": 661.1,
      "interference_score_ms": 39.7
    },
    {
      "id": "s99",
      "excluded": true,
      "reason": "impossibly fast RT (mean < 50ms)"
    }
  ],
  "group_mean_interference_ms": 42.3
}
```

## Verification Criteria

1. **Output file exists and is valid JSON** (10 pts)
2. **s99 correctly excluded** (20 pts)
3. **All 27 real participants present** (20 pts)
4. **Interference scores within ±15ms for ≥20 of 27 participants** (30 pts)
5. **Group mean interference within ±8ms of ground truth** (20 pts)

Pass threshold: 60 pts

## Data Source

Real Eriksen Flanker task data from the PEBL battery validation dataset (participants s1–s27). Participant s99 with impossible RTs is injected programmatically in setup_task.sh as contamination.

## Strategy Enumeration (Anti-Gaming Check)

| Strategy | s99 excluded | 27 present | Scores correct | Group mean | Total |
|----------|:------------:|:----------:|:--------------:|:----------:|:-----:|
| Do-nothing | 0 | 0 | 0 | 0 | 0 |
| Exclude all | +20 | 0 | 0 | 0 | 20 |
| Keep all (no exclusion) | 0 | +20 | partial | partial | <60 |
| Correct behavior | +20 | +20 | +30 | +20 | 100 |
