# Task: Nighttime COLREGS Assessment Scenario Creation

## Domain Context
Maritime training instructors at institutions like Warsash Maritime School use Bridge Command to create assessment scenarios for cadet officers. A critical competency is applying COLREGS (International Regulations for Preventing Collisions at Sea) in reduced visibility or nighttime conditions. This task simulates a real instructor workflow: building a multi-vessel night scenario that tests cadets on the three primary encounter types.

## Goal
Create a complete nighttime COLREGS assessment exercise in Bridge Command's Solent environment. The agent must:

1. **Create a scenario directory** at `/opt/bridgecommand/Scenarios/n) Solent COLREGS Night Assessment/` with three INI files
2. **Configure environment** for nighttime conditions in the Solent
3. **Place own vessel** at realistic Solent coordinates
4. **Create 4 traffic vessels** representing head-on, crossing, overtaking, and restricted manoeuvrability encounters
5. **Configure radar/ARPA** in bc5.ini for the assessment
6. **Write an assessment briefing** document

## Success Criteria

### Criterion 1: Scenario Structure (20%)
- Scenario directory exists with environment.ini, ownship.ini, othership.ini

### Criterion 2: Environment Configuration (15%)
- Setting is "Solent", nighttime start (22:00-04:00), good visibility (>= 5nm), calm weather (<= 2.0)

### Criterion 3: Own Ship Placement (10%)
- Named "MV Dorado", real Solent coordinates, reasonable speed/heading

### Criterion 4: Traffic Vessels (25%)
- Exactly 4 vessels with proper waypoint legs
- Must include head-on, crossing, overtaking, and restricted vessel types

### Criterion 5: Radar/ARPA Configuration (15%)
- arpa_on=1, full_radar=1, radar_range_resolution=256, max_radar_range=96

### Criterion 6: Assessment Briefing Document (15%)
- File exists at /home/ga/Documents/colregs_assessment_briefing.txt
- Contains references to COLREGS Rules 13, 14, 15 and all encounter types

## Verification Strategy
- Parse scenario INI files for structure and values
- Check bc5.ini for radar settings
- Check briefing document for required keywords
- Validate coordinates are within Solent bounds

## Data Reference
- Solent coordinates: Lat 50.77-50.82, Long -1.20 to -1.10
- Bridge Command scenario format: environment.ini (flat key=value), ownship.ini (flat key=value), othership.ini (indexed key(N)=value format)
- bc5.ini sections: [RADAR], [Startup]
