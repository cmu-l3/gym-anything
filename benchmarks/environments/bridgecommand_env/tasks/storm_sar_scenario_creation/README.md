# Task: Storm SAR Scenario Creation

## Domain Context
Maritime Rescue Coordination Centre (MRCC) officers create training scenarios for SAR exercises involving multiple vessels in extreme weather. The Lizard Peninsula area off Cornwall is one of the UK's busiest SAR regions due to the convergence of shipping lanes, fishing grounds, and recreational sailing with exposed Atlantic weather.

## Goal
Build a complete SAR training scenario from scratch with 6 vessels (casualties, SAR assets, and commercial traffic) in storm conditions, configure advanced radar for the exercise, and prepare a SAR operations briefing document.

## Success Criteria

### Criterion 1: Scenario Structure (10%)
- Directory with environment.ini, ownship.ini, othership.ini

### Criterion 2: Environment — Storm Conditions (15%)
- Falmouth setting, 0300 start, Weather=8.0, Rain=5.0, Visibility=3.0, January 2025

### Criterion 3: Own Ship — SAR Coordinator (10%)
- RNLI Severn Class, Lizard Point coordinates, GPS/depth enabled

### Criterion 4: Traffic — 6 Vessels with Roles (25%)
- 6 vessels with diverse types and roles (casualties, SAR, commercial)
- Each with 2-3 waypoint legs, realistic speeds

### Criterion 5: Radar Configuration (15%)
- arpa_on=1, full_radar=1, resolution=512, angular=720, range=96

### Criterion 6: SAR Briefing Document (25%)
- 25+ lines with casualty details, datum point, search pattern, comms plan, weather

## Data Reference
- Lizard Point: 49.96N, 5.22W
- MRCC Falmouth VHF: Ch 16 (distress), Ch 67 (SAR coordination)
- Storm force: Beaufort 8+ (Weather=8.0 in BC)
