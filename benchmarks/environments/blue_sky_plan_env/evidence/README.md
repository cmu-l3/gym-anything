# Blue Sky Plan Environment - Evidence Documentation

## Verification Checklist

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | Installation script completes without errors | PASS | `pre_start_log.txt` — "Blue Sky Plan installed successfully", "Mesa OpenGL configured", "Copied 100 DICOM files" |
| 2 | Setup script completes without errors | PASS | `post_start_log.txt` — warm-up launch, dialog dismissal (all 7 phases), "Blue Sky Plan setup complete" |
| 3 | Application is visible in screenshot | PASS | All 10 `task_start_state_*.png` screenshots show BSP window with "START NEW PROJECT" hex grid |
| 4 | Application is in correct initial state | PASS | All screenshots show the project type selection screen — no dialogs, no Edge browser, no crash reports |
| 5 | Task setup runs without errors for all 10 tasks | PASS | `pre_task_log_*.txt` — each ends with "task setup complete", BSP process confirmed running |
| 6 | Task start state is correct (verified via screenshots) | PASS | Screenshots captured via VNC after task setup for each task |
| 7 | DICOM data available on VM | PASS | Pre-start log: "DICOM directory: C:\Users\Docker\Documents\DentalDICOM (100 files)" |
| 8 | Dialog dismissal handles Edge browser | PASS | All pre_task logs show "Edge killed" in Phases 1, 3, and 7 (late Edge) |
| 9 | Mesa OpenGL software rendering works | PASS | BSP launches without OpenGL 4.3 hard block; pre_task logs show "Copied Mesa opengl32sw.dll" |

## Files in This Directory

### Screenshots (task start states)

Each screenshot was captured by running `env.reset()` from a post_start checkpoint with the given task_id. The screenshots show what the agent sees when it begins each task.

| File | Task | Description |
|------|------|-------------|
| `task_start_state_import_dicom_scan.png` | import_dicom_scan | BSP "START NEW PROJECT" screen. Agent clicks "EASY CT DICOM VIEWER" to import DICOM data from `C:\Users\Docker\Documents\DentalDICOM`. |
| `task_start_state_place_implant.png` | place_implant | BSP "START NEW PROJECT" screen. Agent opens DICOM data, then uses "IMPLANT PLANNING AND SURGICAL GUIDES" to place an implant. |
| `task_start_state_measure_distance.png` | measure_distance | BSP "START NEW PROJECT" screen. Agent loads DICOM data and uses measurement tools to measure ridge-to-canal distance. |
| `task_start_state_adjust_panoramic_curve.png` | adjust_panoramic_curve | BSP "START NEW PROJECT" screen. Agent loads DICOM data and adjusts the panoramic curve in the viewer. |
| `task_start_state_create_surgical_guide.png` | create_surgical_guide | BSP "START NEW PROJECT" screen. Agent loads DICOM data, places implant, and creates a tooth-supported surgical guide. |
| `task_start_state_implant_site_assessment.png` | implant_site_assessment | BSP "START NEW PROJECT" screen. Agent must load DICOM, navigate to 3 mandibular sites, measure bone height/width, annotate, and export cross-sections. (hard) |
| `task_start_state_nerve_canal_mapping.png` | nerve_canal_mapping | BSP "START NEW PROJECT" screen. Agent must load DICOM, trace inferior alveolar nerve, mark foramina, measure ridge-to-canal distances, and save panoramic screenshot. (hard) |
| `task_start_state_multi_implant_plan_with_measurements.png` | multi_implant_plan_with_measurements | BSP "START NEW PROJECT" screen. Agent must place 2+ implants bilaterally (positions #19 and #30) with appropriate sizing and inter-implant measurement. (hard) |
| `task_start_state_anatomical_landmark_annotation.png` | anatomical_landmark_annotation | BSP "START NEW PROJECT" screen. Agent must annotate mental foramen, mandibular canal, maxillary sinus floor, and measure bone height. (hard) |
| `task_start_state_complete_implant_workflow.png` | complete_implant_workflow | BSP "START NEW PROJECT" screen. Agent must complete full implant planning workflow from DICOM import to nerve clearance verification — no detailed guidance. (very_hard) |

### Log Files

| File | Hook | Key Outputs |
|------|------|-------------|
| `pre_start_log.txt` | pre_start (install) | Download 1658 MB installer, install via schtasks, Mesa OpenGL setup, copy 100 DICOM files |
| `post_start_log.txt` | post_start (setup) | Warm-up launch, 7-phase dialog dismissal, force-kill BSP |
| `pre_task_log_import_dicom_scan.txt` | pre_task | Launch BSP, dismiss dialogs, verify BSP running (PID) |
| `pre_task_log_place_implant.txt` | pre_task | Launch BSP fresh, dismiss dialogs, verify BSP running |
| `pre_task_log_measure_distance.txt` | pre_task | Launch BSP, dismiss dialogs, verify BSP running |
| `pre_task_log_adjust_panoramic_curve.txt` | pre_task | Launch BSP, dismiss dialogs, verify BSP running |
| `pre_task_log_create_surgical_guide.txt` | pre_task | Launch BSP fresh, dismiss dialogs, verify BSP running |
| `pre_task_log_implant_site_assessment.txt` | pre_task | Creates output dirs, records timestamp, launches BSP, dismisses dialogs, verifies BSP running |
| `pre_task_log_nerve_canal_mapping.txt` | pre_task | Records timestamp, verifies DICOM (100 slices), launches BSP, dismisses dialogs, verifies BSP running |
| `pre_task_log_multi_implant_plan_with_measurements.txt` | pre_task | Cleans previous outputs, records timestamp, launches BSP, dismisses dialogs, verifies BSP running |
| `pre_task_log_anatomical_landmark_annotation.txt` | pre_task | Creates output dirs, records timestamp, launches BSP, dismisses dialogs, verifies BSP running |
| `pre_task_log_complete_implant_workflow.txt` | pre_task | Cleans previous outputs, records timestamp, launches BSP, dismisses dialogs, verifies BSP running |

## Log Snippets

### pre_start (installation)

```
=== Installing Blue Sky Plan ===
Downloading Blue Sky Plan 5.0.29 installer...
Installer downloaded: 1658.4 MB
Starting installation via interactive session...
BSP Launcher detected at: C:\Program Files\BlueSkyPlan\Launcher\BlueSkyLauncher.exe after 100s
Blue Sky Plan installed successfully.

=== Setting up Mesa software OpenGL ===
Copied opengl32sw.dll -> opengl32.dll in C:\Program Files\BlueSkyPlan\Launcher
Mesa OpenGL configured.

=== Setting up DICOM data ===
Copied 100 DICOM files from workspace.
DICOM directory: C:\Users\Docker\Documents\DentalDICOM (100 files)
=== Blue Sky Plan installation complete ===
```

### post_start (setup with warm-up)

```
=== Setting up Blue Sky Plan environment ===
Disabling Windows Update...
Killing OneDrive...
DICOM data available at: C:\Users\Docker\Documents\DentalDICOM (100 files)
Performing warm-up launch to dismiss first-run dialogs...
Blue Sky Plan launched (waited 30s).
Running dialog dismissal...
=== Dismissing dialogs ===
Phase 0: Hardware warning (if present)...
Phase 1: Killing Edge browser...
  Edge killed
Phase 2: Closing crash report dialog...
Phase 3: Killing Edge...
  Edge killed
Phase 4: Closing login popup (Edge was detected)...
Phase 5: Killing Edge...
Phase 5: Back button cleanup...
Phase 6: Final Escape...
Phase 7: Late Edge cleanup...
  Late Edge detected, cleaning up...
=== Dialog dismissal complete ===
Force-killing BSP after warm-up...
=== Blue Sky Plan setup complete ===
```

### pre_task (example: import_dicom_scan)

```
=== Setting up import_dicom_scan task ===
DICOM data ready at: C:\Users\Docker\Documents\DentalDICOM (100 files)
Copied Mesa opengl32sw.dll -> opengl32.dll in C:\Program Files\BlueSkyPlan\BlueSkyPlan4
Launching Blue Sky Plan...
Blue Sky Plan launched (waited 20s).
Dismissing dialogs...
=== Dismissing dialogs ===
Phase 0: Hardware warning (if present)...
Phase 1: Killing Edge browser...
  Edge killed
...
Phase 7: Late Edge cleanup...
  Late Edge detected, cleaning up...
=== Dialog dismissal complete ===
Blue Sky Plan is running (PID: 5932)
=== import_dicom_scan task setup complete ===
```

### pre_task (example: implant_site_assessment — new hard task)

```
=== Setting up implant_site_assessment task ===
Task start timestamp: 1771888594
DICOM directory found: C:\Users\Docker\Documents\DentalDICOM (100 files)
Blue Sky Plan executable: C:\Program Files\BlueSkyPlan\Launcher\BlueSkyLauncher.exe
Launching Blue Sky Plan (agent will need to load DICOM data)...
Blue Sky Plan launched (waited 25s).
Dismissing dialogs...
=== Dismissing dialogs ===
Phase 0: Hardware warning (if present)...
Phase 1: Killing Edge browser...
  Edge killed
Phase 2: Closing crash report dialog...
Phase 3: Killing Edge...
  Edge killed
Phase 4: Closing login popup (Edge was detected)...
...
Phase 7: Late Edge cleanup...
  Late Edge detected, cleaning up...
=== Dialog dismissal complete ===
Blue Sky Plan is running (PID: 168)
=== implant_site_assessment task setup complete ===
```

### pre_task (example: nerve_canal_mapping — new hard task)

```
=== Setting up nerve_canal_mapping task ===
Task start timestamp: 1771888668
DICOM directory exists with 100 slices at: C:\Users\Docker\Documents\DentalDICOM
Blue Sky Plan executable: C:\Program Files\BlueSkyPlan\Launcher\BlueSkyLauncher.exe
Launching Blue Sky Plan (agent will import DICOM and map nerve canal)...
Blue Sky Plan launched (waited 25s).
=== Dismissing dialogs ===
...
=== Dialog dismissal complete ===
Blue Sky Plan is running (PID: 10320)
=== nerve_canal_mapping task setup complete ===
```

## Do-Nothing Verifier Tests

All 5 new task verifiers correctly reject a do-nothing agent (score=0, passed=False):

| Task | Score | Passed | Feedback |
|------|-------|--------|----------|
| implant_site_assessment | 0/100 | False | All 5 criteria FAIL: no .bsp, no measurements, no annotations, no images |
| nerve_canal_mapping | 0/100 | False | All 5 criteria FAIL: no .bsp, no annotations, no measurements, no screenshot |
| multi_implant_plan_with_measurements | 0/100 | False | Result JSON not found; no project file created |
| anatomical_landmark_annotation | 0/100 | False | All criteria FAIL: no .bsp, no screenshot, no annotation/measurement data |
| complete_implant_workflow | 0/100 | False | No export JSON, no .bsp, no screenshot |

Pass threshold for all tasks: 70/100.

## Task Difficulty and Description Compliance

All 5 new tasks comply with task_creation_notes principles:

| Task | Difficulty | UI Hints in Description | Multi-Criterion Verifier | Realistic Domain Knowledge Required |
|------|-----------|-------------------------|--------------------------|--------------------------------------|
| implant_site_assessment | hard | None — goal only | 5 criteria (100 pts) | Yes — bone height/width measurement at specific dental sites |
| nerve_canal_mapping | hard | None — goal only | 5 criteria (100 pts) | Yes — nerve canal tracing, foramen identification |
| multi_implant_plan_with_measurements | hard | None — goal only | Multi-criterion | Yes — bilateral implant placement, sizing |
| anatomical_landmark_annotation | hard | None — goal only | Multi-criterion | Yes — anatomical structure identification |
| complete_implant_workflow | very_hard | None — high-level goal only | Multi-criterion | Yes — full treatment planning, catalog/size selection |

## Test Configuration

- **Test method**: `gym_anything.api.from_config()` with `cache_level="post_start"`, `use_savevm=False`
- **Reset time per task**: ~138s (68s env setup + 69s pre_task)
- **VM**: Windows 11, QEMU with KVM, 1280x720 resolution
- **Automation**: PyAutoGUI TCP server (port 5555) for click/key input
- **Screenshots**: Captured via VNC
