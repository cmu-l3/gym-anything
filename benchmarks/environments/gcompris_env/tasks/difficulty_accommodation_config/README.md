# Difficulty Accommodation Configuration

## Task Overview

**Occupation**: Special Education Teacher
**Difficulty**: Hard
**Timeout**: 600 seconds / 70 max steps

## Domain Context

Special education teachers regularly configure educational software to meet individual student accommodation needs. When a student has cognitive learning challenges, the teacher must reduce the software's complexity by filtering activities to only the most accessible difficulty levels, personally verify those activities are appropriate, and document the configuration in an Individual Accommodation Plan (IAP) for school records.

## Goal

1. Access the GCompris settings/configuration panel
2. Change the difficulty filter maximum from 6 down to 3 (most accessible activities)
3. Navigate Math and Language categories with the filter applied
4. Run at least 2 accessible activities to verify appropriateness
5. Write an accommodation plan to `~/Desktop/accommodation_plan.txt`

## Success Criteria

The report file `~/Desktop/accommodation_plan.txt` must:
- Be created after the task started
- Be at least 350 bytes
- Mention difficulty, level, or setting changes
- List accessible activities from Math and/or Language categories

Additionally, the GCompris config file at `~/.config/gcompris-qt/gcompris-qt.conf` should show a changed `filterLevelMax` value (reduced from default of 6).

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| Report file exists | 10 |
| Report created after task started (gate) | 10 |
| Report is ≥350 bytes | 10 |
| Report mentions difficulty/level settings | 15 |
| Report lists Math activities | 20 |
| Report lists Language activities | 15 |
| GCompris config filterLevelMax changed from 6 | 20 |

Pass threshold: **60 points**

## GCompris Configuration

The settings panel is accessible through the application interface (typically a gear/wrench icon in the toolbar or footer). Settings include:
- Difficulty range slider (filterLevelMin and filterLevelMax)
- Audio settings
- Fullscreen mode

The config file at `~/.config/gcompris-qt/gcompris-qt.conf` stores:
```ini
[General]
filterLevelMin=1
filterLevelMax=6  ← this should be changed to ≤3
```

## Notes

- This is the only task that requires changing GCompris application settings
- The configuration change is additionally verified via the config file on disk
- Very hard because the agent must discover the settings UI and understand difficulty filtering
