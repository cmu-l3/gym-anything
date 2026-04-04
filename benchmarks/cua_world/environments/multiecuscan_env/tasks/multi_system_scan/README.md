# Multi-System Diagnostic Scan Task

## Overview
Perform a comprehensive multi-system diagnostic scan on a Fiat Punto, scanning Engine, ABS, and Airbag ECUs sequentially.

## Vehicle Details
- **Make/Model**: Fiat Punto (2012)
- **Engine**: 1.4 Turbo (955A3.000)
- **ECU**: Bosch ME 17.3.0

## Task Steps
For each of 3 systems (Engine, ABS, Airbag):
1. Navigate to correct vehicle/module selection
2. Click "Simulate"
3. Read ECU identification from Info screen
4. Press F3 for Errors, read all DTCs
5. Press F11 to disconnect
6. Move to next system

Create report at `C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_report.txt`

## Scoring (100 pts, pass at 60)
- Report exists (10), Timestamp (10)
- Engine section (15), ABS section (15), Airbag section (15)
- ECU identifications (10), DTC codes (10), Overall summary (10)
- VLM navigation (5)
