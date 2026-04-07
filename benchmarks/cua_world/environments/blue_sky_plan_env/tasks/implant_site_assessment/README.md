# implant_site_assessment

## Overview

An oral surgeon needs a pre-implant bone assessment for three sites in the lower right
posterior jaw. The agent must load DICOM data, navigate to each site, measure vertical
bone height and buccolingual width, place annotations/markers, save the project, and
export cross-sectional view images.

**Difficulty:** Hard

## Task Requirements

The agent must independently determine how to:

1. **Load DICOM data** from `C:\Users\Docker\Documents\DentalDICOM` into Blue Sky Plan
2. **Navigate to three assessment sites** in the lower right posterior mandible:
   - Second premolar area
   - First molar area
   - Second molar area
3. **Measure at each site:**
   - Vertical bone height (alveolar ridge crest to inferior alveolar nerve canal)
   - Buccolingual (cheek-to-tongue) bone width
4. **Document each site** with annotations or markers
5. **Save the project** to `C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_assessment.bsp`
6. **Export cross-sectional images** (at least 2) to `C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_images\`

## Why This Task Is Hard

- The task description provides **goals only** -- no UI navigation steps, menu paths, button
  locations, or keyboard shortcuts are given
- The agent must figure out how to load DICOM data, navigate the panoramic/cross-sectional views,
  use the measurement tool, place annotations, save, and export entirely on its own
- Three distinct anatomical sites must be assessed (multi-site workflow)
- Two types of measurements at each site (vertical height + buccolingual width)
- The agent must understand dental anatomy concepts (alveolar ridge, nerve canal, buccolingual)
- Requires coordinating between panoramic view (site selection) and cross-sectional view (measurements)
- Export requires the agent to find and use the image export functionality

## Setup Script (`setup_task.ps1`)

The pre-task script:
1. Kills any existing BSP instances and cleans crash logs
2. Creates output directories (`BlueSkyPlanTasks/` and `BlueSkyPlanTasks/site_images/`)
3. Cleans previous output files
4. Records task start timestamp for anti-gaming verification
5. Verifies DICOM data exists at the expected location
6. Ensures Mesa software OpenGL rendering is configured
7. Launches BSP via `schtasks` for interactive desktop session
8. Dismisses startup dialogs (hardware warning, crash report, login popup, Edge)

## Export Script (`export_result.ps1`)

The post-task script:
1. Reads the task start timestamp
2. Checks .bsp project file existence, size, and modification time
3. Scans the `site_images/` directory for exported images (PNG, JPG, BMP, TIFF)
4. Analyzes the .bsp file as a SQLite database:
   - Searches for annotation/marker/fiducial tables and records
   - Searches for measurement/distance/ruler tables and records
   - Falls back to generic table inspection if specific tables not found
5. Writes structured JSON result to `site_assessment_result.json`

## Verification (`verifier.py`)

Multi-criterion scoring (100 points, pass at 70):

| Criterion | Points | Description |
|-----------|--------|-------------|
| .bsp exists and >100 KB | 20 | Project file saved with substantial content |
| .bsp modified after task start | 20 | Confirms agent created the file during the task |
| Multiple measurements in .bsp | 25 | Measurement/distance data found in SQLite tables |
| Annotation/fiducial data in .bsp | 20 | Markers or annotations placed at assessment sites |
| Cross-section images exported | 15 | At least 2 valid images (>10 KB each) in site_images/ |

### Anti-Tamper

- The verifier independently copies the .bsp file and images from the VM via `copy_from_env`
- Direct SQLite analysis is performed on the copied .bsp, not just the export JSON
- File sizes are cross-checked between direct copy and export script data

### Do-Nothing Test

A do-nothing agent receives score 0 because:
- No .bsp file will exist at the expected path
- No images will exist in the export directory
- All criteria require the agent to have performed actions

### Scoring Details

- **Full credit** on criterion 3 requires 3+ measurement records (ideally 6: 2 per site)
- **Partial credit** given when BSP exists but data tables cannot be identified by keyword
- Measurement count of 1-2 gives 15/25 (some measurements but fewer than expected)
- Single exported image gives 8/15 (task requires at least 2)

## File Structure

```
implant_site_assessment/
  task.json          - Task specification and hooks
  README.md          - This documentation
  setup_task.ps1     - Pre-task setup (launch BSP, create dirs)
  export_result.ps1  - Post-task data export (analyze .bsp + images)
  verifier.py        - Multi-criterion programmatic verifier
```

## Testing

```python
from gym_anything.api import from_config
import os

os.chdir('/path/to/repo')
env = from_config('examples/blue_sky_plan_env', task_id='implant_site_assessment')
obs = env.reset(seed=42, use_cache=True, cache_level='post_start', use_savevm=True)
# Agent interacts with BSP to load DICOM, measure sites, annotate, save, export...
obs, reward, done, info = env.step(action)
```
