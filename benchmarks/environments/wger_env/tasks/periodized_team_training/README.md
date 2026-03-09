# Task: periodized_team_training

## Overview

An athletic trainer for a college basketball team must set up a complete
off-season periodized strength and conditioning program in wger fitness
manager. The task requires creating three training phase routines, each
with two training days that have specific day-of-week assignments.

## Occupation

Athletic Trainer (SOC 29-9091.00) -- Healthcare Practitioners and Technical

## Difficulty

**very_hard** -- The task description specifies WHAT to create but not HOW
to navigate wger's UI. The agent must discover routine creation, day
addition, and day-of-week assignment flows on its own. Nine distinct create
operations are required across multiple UI sections.

## What the agent must create

| Routine                           | Description                                                  | Day 1                  | DoW 1    | Day 2                  | DoW 2     |
|-----------------------------------|--------------------------------------------------------------|------------------------|----------|------------------------|-----------|
| Phase 1 - Anatomical Adaptation   | Weeks 1-4: Movement quality and work capacity foundation     | Upper Body Foundations | Monday   | Lower Body Foundations | Thursday  |
| Phase 2 - Maximal Strength        | Weeks 5-8: Heavy compound lifts for peak force production    | Heavy Upper            | Tuesday  | Heavy Lower            | Friday    |
| Phase 3 - Power Development       | Weeks 9-12: Explosive movements and sport-specific power     | Explosive Upper        | Monday   | Explosive Lower        | Wednesday |

## Scoring (100 points, pass >= 70)

| Criterion | Points | Description                                                    |
|-----------|--------|----------------------------------------------------------------|
| C1        | 12     | Phase 1 routine exists with correct description                |
| C2        | 12     | Phase 2 routine exists with correct description                |
| C3        | 12     | Phase 3 routine exists with correct description                |
| C4        | 8      | Phase 1 has "Upper Body Foundations" day                       |
| C5        | 8      | Phase 1 has "Lower Body Foundations" day                       |
| C6        | 8      | Phase 2 has "Heavy Upper" day                                  |
| C7        | 8      | Phase 2 has "Heavy Lower" day                                  |
| C8        | 8      | Phase 3 has "Explosive Upper" day                              |
| C9        | 8      | Phase 3 has "Explosive Lower" day                              |
| C10       | 16     | At least 4 of 6 days have correct day-of-week assignments      |

## Files

- `task.json` -- Task definition
- `setup_task.sh` -- Pre-task hook: cleans state, records baselines, launches browser
- `export_result.sh` -- Post-task hook: queries DB for routines/days, writes result JSON
- `verifier.py` -- Multi-criterion programmatic verifier
- `README.md` -- This file
