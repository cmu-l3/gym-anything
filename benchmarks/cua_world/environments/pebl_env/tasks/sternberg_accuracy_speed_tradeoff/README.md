# Sternberg Accuracy-Speed Tradeoff (SCAP)

## Task Overview

**Domain**: Cognitive Neuroscience — Working Memory
**Difficulty**: Very Hard
**Occupation**: Cognitive Neuroscientist, Neuropsychologist

A working memory laboratory has collected Spatial Capacity (SCAP) task data from 11 real participants. One additional participant (sub-99999) has been injected with impossible data (100% accuracy + RT=50-80ms), simulating a robotic auto-responder artifact. The data is at `~/pebl/data/sternberg_data.csv`.

## Goal

Compute mean accuracy and mean RT per set size per participant, identify the corrupted participant, and produce a JSON report at `~/pebl/analysis/sternberg_analysis.json`.

## Data Format

`sternberg_data.csv` columns:
- `participant_id`: participant ID (e.g., sub10159)
- `set_size`: number of spatial locations (1, 3, 5, or 7)
- `trial`: trial number within set_size
- `correct`: 1=correct response, 0=error
- `response_time_ms`: response time in milliseconds

## Output Format

```json
{
  "participants": [
    {
      "id": "sub10159",
      "set_sizes": {
        "1": {"mean_acc": 0.75, "mean_rt_ms": 1088.2},
        "3": {"mean_acc": 0.58, "mean_rt_ms": 1219.4},
        "5": {"mean_acc": 0.42, "mean_rt_ms": 1472.5},
        "7": {"mean_acc": 0.67, "mean_rt_ms": 1359.5}
      }
    },
    {"id": "sub-99999", "excluded": true, "reason": "100% accuracy with RT<100ms"}
  ],
  "group_means": {
    "1": {"mean_acc": 0.925, "mean_rt_ms": 980.9},
    "3": {"mean_acc": 0.839, "mean_rt_ms": 1118.7},
    "5": {"mean_acc": 0.810, "mean_rt_ms": 1210.5},
    "7": {"mean_acc": 0.765, "mean_rt_ms": 1260.7}
  }
}
```

## Verification Criteria

1. **Output file exists and is valid JSON** (10 pts)
2. **sub-99999 correctly excluded** (25 pts)
3. **Mean accuracy within ±10% for ≥8 of 11 valid participants** (30 pts)
4. **Mean RT within ±150ms for ≥8 of 11 valid participants** (20 pts)
5. **Group means by set size correct within tolerance** (15 pts)

Pass threshold: 60 pts

## Data Source

Real CNP OpenNeuro ds000030 SCAP (Spatial Capacity / Working Memory) data (11 participants).
Citation: Gorgolewski, K.J., et al. (2017). *Scientific Data*, 4, 170036. doi:10.1038/sdata.2017.93

sub-99999 is injected by setup_task.sh with 100% accuracy and RT=50-80ms (impossible for human working memory performance).
