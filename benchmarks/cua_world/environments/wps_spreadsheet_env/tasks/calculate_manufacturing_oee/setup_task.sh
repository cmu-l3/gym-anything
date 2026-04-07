#!/bin/bash
echo "=== Setting up calculate_manufacturing_oee task ==="

LOGS_FILE="/home/ga/Documents/production_logs.xlsx"

# Remove any existing files
rm -f "$LOGS_FILE" 2>/dev/null || true

# Generate realistic manufacturing data using Python
python3 << 'PYEOF'
import random
from datetime import datetime, timedelta
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = 'Shift Logs'

headers = ['Date', 'Shift', 'Machine_ID', 'Planned_Minutes', 'Downtime_Minutes', 'Ideal_Cycle_Time_sec', 'Total_Parts', 'Defect_Parts']
ws.append(headers)

start_date = datetime(2023, 10, 1)
machines = {
    'CNC-01': 45, # 45 seconds ideal cycle time
    'CNC-02': 60, # 60 seconds
    'CNC-03': 30  # 30 seconds
}

# Generate 60 rows of data
for day in range(20):
    current_date = (start_date + timedelta(days=day)).strftime('%Y-%m-%d')
    for machine, cycle_time in machines.items():
        planned_mins = 480 # 8 hour shift
        # Simulate some bad days and good days
        if random.random() < 0.2:
            downtime = random.randint(90, 180) # Major breakdown
        else:
            downtime = random.randint(15, 45)  # Minor stops
            
        operating_time = planned_mins - downtime
        
        # Performance variance (operator efficiency)
        perf_factor = random.uniform(0.85, 0.98)
        max_parts = int((operating_time * 60) / cycle_time)
        total_parts = int(max_parts * perf_factor)
        
        # Quality variance
        if random.random() < 0.15:
            defect_rate = random.uniform(0.05, 0.12) # High defect day
        else:
            defect_rate = random.uniform(0.005, 0.03) # Normal
        defect_parts = int(total_parts * defect_rate)
        
        ws.append([
            current_date,
            1, # Shift 1
            machine,
            planned_mins,
            downtime,
            cycle_time,
            total_parts,
            defect_parts
        ])

# Formatting
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 8
ws.column_dimensions['C'].width = 14
ws.column_dimensions['D'].width = 18
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 20
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 14

wb.save('/home/ga/Documents/production_logs.xlsx')
print("Created production_logs.xlsx with 60 rows of realistic manufacturing data")

PYEOF

chown ga:ga "$LOGS_FILE" 2>/dev/null || true

# Record start time for verification
date +%s > /tmp/task_start_time.txt

# Launch WPS Spreadsheet with the production logs file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$LOGS_FILE"

echo "=== Task setup complete ==="