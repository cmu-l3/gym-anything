# Task: Restricted Visibility Emergency Drill

## Domain Context
Ship Masters are required by SOLAS and ISM Code to conduct regular emergency drills, including restricted visibility navigation. Dense fog is one of the most dangerous conditions at sea — collisions in fog account for a disproportionate number of maritime casualties. Officers must demonstrate competence in COLREGS Rule 19 (Restricted Visibility), Rule 6 (Safe Speed), and Rule 35 (Sound Signals).

## Goal
Configure a complete fog drill exercise by modifying an existing scenario, adjusting radar settings, and creating a comprehensive safety checklist. This requires modifying files in multiple locations and understanding maritime fog navigation procedures.

## Success Criteria

### Criterion 1: Environment Modified (15%)
- VisibilityRange=0.5, Weather=1.0, Rain=0.0, StartTime=8.0

### Criterion 2: Own Ship Modified (15%)
- Name changed to "MV Caution", speed reduced to 5.0 knots

### Criterion 3: Traffic Vessels Modified (20%)
- Third vessel added (Cargo, near-collision course)
- Existing vessel speeds halved
- Number=3

### Criterion 4: Radar/ARPA for Fog (15%)
- full_radar=1, arpa_on=1, radar_range_resolution=256, max_radar_range=48

### Criterion 5: Fog Drill Checklist (35%)
- File exists with 10+ numbered items
- Covers Rule 5, 6, 19, 35, radar, engine readiness

## Data Reference
- Original scenario: 2 vessels (Tanker speed 8/6/4, Yacht speed 5/5)
- Halved speeds: Tanker ~4/3/2, Yacht ~3/3
- Own ship original: Lat 50.7750, Long -1.1020, Speed 8.0
