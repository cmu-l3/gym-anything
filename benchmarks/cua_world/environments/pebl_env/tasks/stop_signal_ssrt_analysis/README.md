# Stop Signal SSRT Analysis

## Task Overview

**Domain**: Cognitive Neuroscience / Clinical Neuropsychology — Inhibitory Control
**Difficulty**: Very Hard
**Occupation**: Cognitive Neuroscientist, Clinical Neuropsychologist, ADHD Researcher

A cognitive neuroscience laboratory has collected Stop Signal Task data from 11 real participants (CNP OpenNeuro ds000030). One additional participant (sub-99999) has been injected with impossibly fast GO reaction times (15–25 ms), simulating a robotic auto-responder artifact. The dataset is at `~/pebl/data/stopsignal_data.csv`.

## Background: Stop Signal Task (SST)

The SST measures response inhibition — the ability to cancel an already-initiated action. On most trials ("Go" trials), participants respond to a directional arrow. On some trials ("Stop" trials), a stop signal appears after the Go stimulus, instructing the participant to cancel their response. The task is designed so that stopping is difficult (~50% success rate), controlled by an adaptive stop signal delay (SSD).

## Goal

Compute Stop Signal Reaction Time (SSRT) for each valid participant using the **integration method** and produce a JSON report at `~/pebl/analysis/ssrt_report.json`.

## Data Format

`stopsignal_data.csv` columns:
- `participant_id`: participant ID (e.g., sub-10159)
- `trial_type`: GO or STOP
- `go_rt_ms`: reaction time on Go trials in ms (0 for Stop trials or missed Go trials)
- `stop_signal_delay_ms`: SSD for Stop trials in ms (0 for Go trials)
- `outcome`: SuccessfulGo, UnuccessfulGo, UnsuccessfulStop, SuccessfulStop, or JUNK (invalid)

## SSRT Integration Method

1. Extract Go RTs from all `SuccessfulGo` trials
2. For all `STOP` trials: compute p(respond|stop) = UnsuccessfulStop_count / total_STOP_trials
3. Find the nth percentile of the Go RT distribution where n = p(respond|stop)
4. SSRT = nth_percentile_GoRT − mean(stop_signal_delay_ms for all STOP trials)

Typical SSRT values for healthy adults: 150–350 ms.

## Output Format

```json
{
  "participants": [
    {"id": "sub-10159", "ssrt_ms": 192.9},
    {"id": "sub-99999", "excluded": true, "reason": "GO RT < 30ms (physiologically impossible)"}
  ],
  "group_mean_ssrt_ms": 247.4
}
```

## Verification Criteria

1. **Output file exists and is valid JSON** (10 pts)
2. **sub-99999 correctly excluded** (25 pts)
3. **SSRT within ±50ms for ≥8 of 11 valid participants** (35 pts)
4. **Group mean SSRT within ±30ms of ground truth (247.4ms)** (30 pts)

Pass threshold: 60 pts

## Data Source

Real CNP OpenNeuro ds000030 Stop Signal Task data (11 participants).
Citation: Gorgolewski, K.J., et al. (2017). A high-resolution 7-Tesla resting-state fMRI test-retest dataset with cognitive and physiological measures. *Scientific Data*, 4, 170036. doi:10.1038/sdata.2017.93

sub-99999 is injected by setup_task.sh with GO RT=15–25ms (impossible for humans; minimum human RT is ~100ms) and 100% SuccessfulStop rate (impossible for SST which uses adaptive SSD to achieve ~50% stop success).

## Strategy Enumeration (Anti-Gaming Check)

| Strategy | sub-99999 excluded | SSRT correct | Group mean | Total |
|----------|:------------------:|:------------:|:----------:|:-----:|
| Do-nothing | 0 | 0 | 0 | 0 |
| Exclude all | +25 | 0 | 0 | 25 |
| Include sub-99999 | 0 | partial | wrong | <60 |
| Correct behavior | +25 | +35 | +30 | 100 |
