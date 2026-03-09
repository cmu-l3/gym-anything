# Parameter Monitoring & Export Task

## Overview
Monitor live engine parameters on an Alfa Romeo MiTo in simulation mode, view graphs, and create an analysis report comparing against normal ranges and real-world data.

## Vehicle Details
- **Make/Model**: Alfa Romeo MiTo
- **Engine**: 1.4 MultiAir Turbo (955A7.000)
- **ECU**: Bosch ME 17.3.0

## Task Steps
1. Select Alfa Romeo > MiTo > Engine > Bosch ME 17.3.0
2. Click "Simulate"
3. F4 for Parameters, select: RPM, Coolant Temp, Battery V, Throttle
4. Observe values for 10+ seconds
5. F5 for Graph view
6. Create report at `C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_analysis.txt`

## Reference Data
- `obd2_parameter_reference.csv` - Normal ranges per SAE J1979
- `real_obd_drive_session.csv` - Real driving session OBD data
- `real_obd_idle_session.csv` - Real idle session OBD data

## Scoring (100 pts, pass at 60)
- Report exists (10), Timestamp (10)
- Parameters mentioned (20), Numeric values (15)
- Min/Max/Avg (10), Normal ranges (10), Assessment (10)
- Real data comparison (10), VLM graph (5)
