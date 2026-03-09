# Task: Channel Passage Planning Exercise

## Domain Context
Second Officers and Navigation Officers are responsible for passage planning — preparing detailed plans for transits through congested or hazardous waterways. The Dover Strait is one of the world's busiest shipping lanes, with Traffic Separation Schemes (TSS), cross-channel ferry traffic, and restricted visibility common in autumn/winter.

## Goal
Create a complete Dover Strait passage planning exercise in Bridge Command, including a properly structured scenario with 5 traffic vessels representing typical Channel traffic, and a comprehensive passage plan document.

## Success Criteria

### Criterion 1: Scenario Structure (15%)
- Directory exists with environment.ini, ownship.ini, othership.ini

### Criterion 2: Environment Configuration (15%)
- English Channel East setting, pre-dawn start, moderate weather, November

### Criterion 3: Own Ship (10%)
- Named "MV Northern Crown", Dover Strait coordinates, heading SW, 12 kts

### Criterion 4: Traffic Vessels (25%)
- 5 vessels: container ship, tanker, ferry, fishing vessel, sailing yacht
- Each with 2-3 waypoint legs and realistic speeds

### Criterion 5: Radar Configuration (15%)
- full_radar=1, max_radar_range=72, radar_angular_resolution=720, hide_instruments=0

### Criterion 6: Passage Plan Document (20%)
- Contains waypoints, speed, hazards, TSS, VHF communications

## Data Reference
- Dover Strait coordinates: Lat ~51.05-51.15, Long ~1.20-1.40
- TSS Dover Strait: SW lane around 51.0N, NE lane around 51.1N
- Cross-channel ferry routes: Dover-Calais (~51.0N, 1.3-1.9E)
