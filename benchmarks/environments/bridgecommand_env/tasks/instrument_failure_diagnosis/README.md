# Task: Instrument Failure Diagnosis

## Domain Context
Electronics officers and ship engineers must diagnose and repair bridge instrument failures, often under pressure. After electrical surges, multiple systems can fail simultaneously, requiring systematic troubleshooting across both hardware (simulated by config) and software (scenario files).

## Goal
Diagnose and repair 6 deliberate faults injected across Bridge Command's configuration and scenario files. Write a comprehensive fault diagnosis report documenting each fault.

## Faults (6 total, hidden from agent)
3 faults in bc5.ini configuration:
- View angle set to unusable value
- Radar range resolution degraded
- Max radar range severely limited

3 faults in scenario files:
- Visibility set to near-zero
- Own ship speed set to unrealistically high value
- All traffic vessels removed

## Success Criteria

### Criterion 1: bc5.ini Faults Fixed (30 pts, 10 each)
- view_angle restored to 90
- radar_range_resolution restored to 128
- max_radar_range restored to 48

### Criterion 2: Scenario Faults Fixed (30 pts, 10 each)
- VisibilityRange restored to 10.0
- InitialSpeed restored to 8.0 (realistic value)
- Number of vessels restored to 2

### Criterion 3: Fault Report (40 pts)
- Report file exists at /home/ga/Documents/fault_report.txt
- Describes all 6 faults with locations and values
- Contains technical terminology

## Verification Strategy
- Read corrected bc5.ini values from all config locations
- Parse corrected scenario INI files
- Analyze fault report for completeness and accuracy
