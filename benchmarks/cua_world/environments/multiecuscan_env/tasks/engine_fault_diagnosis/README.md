# Engine Fault Diagnosis Task

## Overview
Perform a complete engine fault diagnosis on a Fiat 500 1.3 MultiJet Diesel using Multiecuscan in simulation mode.

## Vehicle Details
- **Make/Model**: Fiat 500
- **Engine**: 1.3 MultiJet Diesel (199B1.000)
- **ECU**: Bosch EDC16C39
- **Protocol**: CAN bus

## Task Steps
1. Navigate to Fiat > 500 > Engine system > Bosch EDC16C39
2. Click "Simulate" to connect in simulation mode
3. Read ECU identification from Info screen
4. Press F3 for Errors screen, read all DTCs
5. Press F4 for Parameters, select RPM, Coolant Temp, Battery V, Throttle
6. Create diagnostic report at `C:\Users\Docker\Desktop\MultiecuscanTasks\engine_diagnostic_report.txt`

## Report Requirements
- ECU Identification (part number, HW/SW versions)
- DTC codes with descriptions (cross-reference dtc_database_full.csv)
- Parameter readings with normal range assessment
- Recommendations for each fault

## Reference Data
- `C:\Users\Docker\Desktop\MultiecuscanData\dtc_database_full.csv` - Real OBD-II DTC database
- `C:\Users\Docker\Desktop\MultiecuscanData\obd2_parameter_reference.csv` - Parameter ranges
- `C:\Users\Docker\Desktop\MultiecuscanData\diagnostic_procedures.txt` - Procedures guide

## Scoring (100 pts, pass at 60)
- Report file exists (15 pts)
- Timestamp valid (10 pts)
- ECU info section (15 pts)
- DTC section with valid codes (20 pts)
- Parameter section (20 pts)
- Recommendations (10 pts)
- VLM trajectory (10 pts)
