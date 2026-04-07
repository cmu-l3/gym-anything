# Stroop Color Lab Protocol Repair

## Task Overview

**Domain**: Experimental Psychology — Laboratory Protocol Management
**Difficulty**: Very Hard
**Occupation**: Research Coordinator, Experimental Psychologist

A multi-site Color-Naming Stroop replication study has had its protocol configuration file corrupted. ALL five experimental parameters were overwritten with wrong values. The lab has confirmed the canonical protocol comes from Steinhauser & Huebner (2009). The file is at `~/pebl/lab/stroop_protocol.json`.

## Goal

Correct all 5 parameter errors in `~/pebl/lab/stroop_protocol.json` so the file matches the published canonical protocol values.

## File Location

`/home/ga/pebl/lab/stroop_protocol.json`

## Injected Errors (5 total)

All five `parameters` fields are wrong:
- `practice_trials`: wrong (correct: 12)
- `test_trials_per_block`: wrong (correct: 48)
- `blocks`: wrong (correct: 4)
- `isi_ms`: wrong (correct: 500)
- `response_colors`: wrong (correct: ["red","blue","green","yellow"])

## Verification Criteria

1. **File is valid JSON** (10 pts)
2. **practice_trials == 12** (15 pts)
3. **test_trials_per_block == 48** (15 pts)
4. **blocks == 4** (20 pts)
5. **isi_ms == 500** (15 pts)
6. **response_colors == ["red","blue","green","yellow"]** (25 pts)

Pass threshold: 60 pts

## Reference

Steinhauser, M., & Huebner, R. (2009). Distinguishing response conflict and task conflict in the Stroop task: Evidence from ex-Gaussian distribution analysis. *Journal of Experimental Psychology: Human Perception and Performance, 35*(5), 1398–1412.
