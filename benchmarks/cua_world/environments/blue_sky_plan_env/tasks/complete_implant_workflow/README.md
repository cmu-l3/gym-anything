# complete_implant_workflow

## Overview
End-to-end dental implant treatment planning workflow in Blue Sky Plan 5.0.
This is a **very_hard** task that combines DICOM import, panoramic curve adjustment,
implant placement, anatomical measurement, project saving, and screenshot export
into a single multi-step workflow.

## What the Agent Must Do
1. Import DICOM scan from `C:\Users\Docker\Documents\DentalDICOM`
2. Adjust the panoramic curve to follow the dental arch
3. Place a BlueSkyBio implant (4.0mm x 10mm) at tooth position #30 (lower right first molar)
4. Measure distance from implant apex to mandibular canal
5. Save treatment plan to `C:\Users\Docker\Desktop\BlueSkyPlanTasks\complete_plan.bsp`
6. Export cross-sectional screenshot to `C:\Users\Docker\Desktop\BlueSkyPlanTasks\complete_plan_screenshot.png`

## Pre-Task Setup (`setup_task.ps1`)
- Kills any existing BSP processes
- Deletes crash logs to prevent crash-recovery dialogs
- Creates output directory `BlueSkyPlanTasks`
- Records task start timestamp
- Sets up Mesa software OpenGL
- Launches Blue Sky Plan fresh (agent imports DICOM)
- Dismisses startup dialogs

## Post-Task Export (`export_result.ps1`)
- Checks existence and size of `.bsp` project file
- Checks existence and size of screenshot file
- Attempts SQLite analysis of `.bsp` file for implant/measurement data
- Writes structured JSON result to `complete_workflow_result.json`

## Verification (`verifier.py`)
Multi-criterion scoring (100 points total, pass at 70):

| Criterion | Points | Description |
|-----------|--------|-------------|
| Project file exists and substantial | 15 | `.bsp` file > 200KB |
| Project modified after task start | 15 | File timestamp check |
| Project contains implant data | 20 | File > 500KB or SQLite implant tables |
| Screenshot exists and substantial | 15 | `.png` file > 50KB |
| Implant-specific data present | 20 | SQLite table analysis for implant records |
| Measurement data present | 15 | SQLite table analysis for measurement records |

Anti-tamper: verifier independently copies `.bsp` and `.png` files from the VM
(does not rely solely on the export JSON).

## File Layout
```
complete_implant_workflow/
  task.json           - Task definition with hooks, metadata, scoring
  README.md           - This file
  setup_task.ps1      - Pre-task hook: launch BSP fresh
  export_result.ps1   - Post-task hook: collect results as JSON
  verifier.py         - Multi-criterion verifier (100pt scale)
```
