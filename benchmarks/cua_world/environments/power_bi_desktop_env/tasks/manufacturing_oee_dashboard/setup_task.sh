#!/bin/bash
# Note: In the Power BI env, we use PowerShell for hooks, but the framework expects
# a .sh file or a command line. The hook definition in task.json points to a .ps1.
# However, to be consistent with the instructions, I will provide the content 
# as a bash script that writes the PowerShell script, OR just standard bash if 
# the environment supports bash (which the Windows env usually does via git-bash or cygwin, 
# but the env spec says "powershell" in hooks). 
# 
# ADAPTING STRATEGY: The env spec shows `powershell -File ...` in hooks.
# I will provide the content that should go into the file referenced in hooks.
# Since I am generating files, I will generate the PowerShell script wrapper.

# BUT wait, the instructions say "Create these files... setup_task.sh". 
# I will create a setup_task.sh that generates the necessary PowerShell script 
# and executes it, OR simply write the PowerShell script if the agent expects .ps1.
# 
# Given the instructions "setup_task.sh - Pre-task setup script", I will provide 
# a bash script that handles the setup logic, compatible with the Windows environment 
# if it has bash, OR I will provide the .ps1 content wrapped in a way that the 
# file generator understands.
#
# Assumption: The environment has a bash shell available (e.g. Git Bash) or 
# I should provide the .ps1 content. Looking at previous examples (Example 6, 7, 8),
# they use `setup_task.ps1`. 
#
# I will provide a `setup_task.sh` that writes and executes the PowerShell logic 
# to ensure compatibility with the requested file format while working in Windows.

echo "=== Generating Setup Script for Windows ==="

# Create the data generation script in Python (bundled in the setup)
mkdir -p /workspace/tasks/manufacturing_oee_dashboard

cat << 'EOF' > /workspace/tasks/manufacturing_oee_dashboard/setup_task.ps1
$ErrorActionPreference = "Stop"
Write-Output "=== Setting up OEE Dashboard Task ==="

# 1. Define paths
$DesktopPath = "C:\Users\Docker\Desktop"
$TaskDir = "$DesktopPath\PowerBITasks"
$DataPath = "$TaskDir\production_log.csv"
$GroundTruthPath = "C:\workspace\tasks\manufacturing_oee_dashboard\ground_truth.json"

# 2. Create directory
if (!(Test-Path -Path $TaskDir)) {
    New-Item -ItemType Directory -Path $TaskDir | Out-Null
}

# 3. Generate Data (Python)
$PythonScript = @"
import csv
import random
import json
import os

machines = ['M-101', 'M-102', 'M-103', 'M-201', 'M-202']
shifts = ['Day', 'Night']
records = []
machine_stats = {m: {'scheduled': 0, 'downtime': 0, 'total_units': 0, 'scrap': 0, 'ideal_cycle_sum': 0, 'count': 0} for m in machines}

# Generate 50 records
for i in range(50):
    date = f'2023-10-{random.randint(1, 31):02d}'
    machine = random.choice(machines)
    shift = random.choice(shifts)
    
    # Logic: 480 min shift (8 hours)
    scheduled = 480
    # Downtime 0-60 mins
    downtime = random.randint(0, 60)
    
    # Ideal cycle: e.g., 30 seconds per unit
    ideal_cycle = random.randint(20, 60)
    
    # Max theoretical units = (RunTime * 60) / IdealCycle
    run_time = scheduled - downtime
    max_units = int((run_time * 60) / ideal_cycle)
    
    # Actual units (85-99% of max)
    total_units = int(max_units * random.uniform(0.85, 0.99))
    
    # Scrap (0-5% of total)
    scrap_units = int(total_units * random.uniform(0.0, 0.05))
    
    records.append([date, machine, shift, scheduled, downtime, total_units, scrap_units, ideal_cycle])
    
    # Accumulate for ground truth
    machine_stats[machine]['scheduled'] += scheduled
    machine_stats[machine]['downtime'] += downtime
    machine_stats[machine]['total_units'] += total_units
    machine_stats[machine]['scrap'] += scrap_units
    machine_stats[machine]['ideal_cycle_sum'] += ideal_cycle
    machine_stats[machine]['count'] += 1

# Write CSV
with open(r'$DataPath', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Date', 'Machine_ID', 'Shift', 'Scheduled_Time_Min', 'Downtime_Min', 'Total_Units', 'Scrap_Units', 'Ideal_Cycle_Seconds'])
    writer.writerows(records)

# Calculate Ground Truth OEE per machine
ground_truth = {}
for m, stats in machine_stats.items():
    if stats['scheduled'] == 0: continue
    
    avail = (stats['scheduled'] - stats['downtime']) / stats['scheduled']
    qual = (stats['total_units'] - stats['scrap']) / stats['total_units']
    
    # Average Ideal Cycle
    avg_ideal = stats['ideal_cycle_sum'] / stats['count']
    
    # Performance = (Total * (AvgIdeal / 60)) / RunTime
    run_time = stats['scheduled'] - stats['downtime']
    perf = (stats['total_units'] * (avg_ideal / 60)) / run_time
    
    oee = avail * qual * perf
    
    ground_truth[m] = {
        'Availability_Pct': round(avail, 4),
        'Quality_Pct': round(qual, 4),
        'Performance_Pct': round(perf, 4),
        'OEE_Score': round(oee, 4)
    }

with open(r'$GroundTruthPath', 'w') as f:
    json.dump(ground_truth, f)

print('Data generation complete.')
"@

# Execute Python data generation
$PythonScript | Out-File -FilePath "$TaskDir\generate_data.py" -Encoding ASCII
python "$TaskDir\generate_data.py"

# 4. Timestamp
$UnixTime = [int][double]::Parse((Get-Date -UFormat %s))
$UnixTime | Out-File -FilePath "C:\workspace\tasks\manufacturing_oee_dashboard\start_time.txt" -Encoding ASCII

# 5. Clean state
$PbixPath = "$DesktopPath\OEE_Dashboard.pbix"
$CsvPath = "$DesktopPath\machine_oee_summary.csv"
if (Test-Path $PbixPath) { Remove-Item $PbixPath -Force }
if (Test-Path $CsvPath) { Remove-Item $CsvPath -Force }

# 6. Ensure Power BI is running
if (!(Get-Process "PBIDesktop" -ErrorAction SilentlyContinue)) {
    Write-Output "Starting Power BI Desktop..."
    Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    Start-Sleep -Seconds 15
}

# 7. Maximize Window (using WASP or similar if available, else relying on user/default)
# PowerShell naive maximize approach
$wshell = New-Object -ComObject Wscript.Shell
$wshell.AppActivate("Power BI Desktop")
Start-Sleep -Seconds 1

Write-Output "=== Setup Complete ==="
EOF

# Execute the PowerShell script we just created
powershell -ExecutionPolicy Bypass -File /workspace/tasks/manufacturing_oee_dashboard/setup_task.ps1