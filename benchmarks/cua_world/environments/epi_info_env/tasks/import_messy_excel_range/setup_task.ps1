# Note: The environment is Windows, so this is actually a PowerShell script wrapper or content.
# Since the environment specification uses .ps1 in hooks, I will provide the content 
# that should go into setup_task.ps1.

# <file name="setup_task.ps1">
Write-Host "=== Setting up Import Messy Excel Task ==="

# Define paths
$DocDir = "C:\Users\Docker\Documents"
$ExcelPath = "$DocDir\VirologyReport.xlsx"
$ProjectDir = "$DocDir\Epi Info 7\Projects\LabImport"
$StartTimePath = "C:\tmp\task_start_time.txt"

# Create temp dir if not exists
if (-not (Test-Path "C:\tmp")) { New-Item -ItemType Directory -Path "C:\tmp" | Out-Null }

# Record start time for anti-gaming
[int][double]::Parse((Get-Date -UFormat %s)) | Out-File $StartTimePath -Encoding ASCII

# 1. Clean up previous run artifacts
Write-Host "Cleaning up previous runs..."
if (Test-Path $ExcelPath) { Remove-Item $ExcelPath -Force }
if (Test-Path $ProjectDir) { Remove-Item $ProjectDir -Recurse -Force }

# 2. Generate the "Messy" Excel File using Python
# We use Python to ensure we get a real .xlsx binary, not a CSV renamed
Write-Host "Generating messy Excel report..."

$PyScript = @"
import pandas as pd
import numpy as np
import os
from datetime import datetime, timedelta

# Create realistic data
np.random.seed(42)
n_rows = 51
dates = [datetime(2025, 5, 12) - timedelta(days=x) for x in range(n_rows)]
ids = [f'V-2025-{i:03d}' for i in range(1, n_rows + 1)]
p_ids = [f'P-{np.random.randint(10000, 99999)}' for _ in range(n_rows)]
results = np.random.choice(['Detected', 'Not Detected'], n_rows, p=[0.3, 0.7])
ct_values = []
for r in results:
    if r == 'Detected':
        ct_values.append(round(np.random.uniform(18.5, 36.0), 2))
    else:
        ct_values.append(0.0)

df_data = pd.DataFrame({
    'SpecimenID': ids,
    'PatientID': p_ids,
    'CollectionDate': dates,
    'TestResult': results,
    'CtValue': ct_values
})

# Create a writer
file_path = r'C:\Users\Docker\Documents\VirologyReport.xlsx'
writer = pd.ExcelWriter(file_path, engine='xlsxwriter')

# Write 'Junk' headers (The Messy Part)
workbook = writer.book
worksheet = workbook.add_worksheet('Sheet1')
writer.sheets['Sheet1'] = worksheet

# Add formats
bold = workbook.add_format({'bold': True, 'font_size': 14})
italic = workbook.add_format({'italic': True})

# Write Top Matter (Rows 1-3)
worksheet.write('A1', 'St. Mary\'s Hospital - Virology Dept', bold)
worksheet.write('A2', 'Report Date: 2025-05-12', italic)
worksheet.write('A3', 'CONFIDENTIAL - DO NOT DISTRIBUTE')

# Write Header on Row 4 (0-indexed is 3)
headers = df_data.columns.tolist()
for col_num, value in enumerate(headers):
    worksheet.write(3, col_num, value, bold)

# Write Data starting Row 5 (0-indexed is 4)
for row_num, row_data in enumerate(df_data.values):
    for col_num, value in enumerate(row_data):
        # Convert pandas/numpy types to native python for xlsxwriter
        val = value
        if hasattr(value, 'item'): val = value.item() 
        # Handle dates
        if isinstance(val, (np.datetime64, pd.Timestamp)):
            val = val.strftime('%Y-%m-%d')
            
        worksheet.write(row_num + 4, col_num, val)

writer.close()
print(f"Created {file_path}")
"@

$PyScriptPath = "C:\tmp\generate_excel.py"
$PyScript | Out-File $PyScriptPath -Encoding UTF8

# Execute Python script
python $PyScriptPath

# 3. Ensure Epi Info 7 is running
Write-Host "Ensuring Epi Info 7 is running..."
$EpiProc = Get-Process "EpiInfo" -ErrorAction SilentlyContinue
if (-not $EpiProc) {
    Start-Process "C:\Epi Info 7\EpiInfo.exe"
    Start-Sleep -Seconds 5
}

# 4. Maximize Window
Write-Host "Maximizing window..."
# (Requires nircmd or similar in env, or skipped if not available. 
# Windows envs usually handle this via the gym wrapper, but we try anyway)
try {
    $wshell = New-Object -ComObject Wscript.Shell
    $wshell.AppActivate("Epi Info")
    Start-Sleep -Milliseconds 500
    $wshell.SendKeys("% x") # Alt+Space, x to maximize
} catch {
    Write-Host "Could not maximize window via shell."
}

# 5. Take Initial Screenshot
Write-Host "Capturing initial state..."
# Using python for screenshot if scrot not available on Windows
$ScreenScript = @"
import pyautogui
try:
    pyautogui.screenshot(r'C:\tmp\task_initial.png')
except:
    pass
"@
$ScreenScript | Out-File "C:\tmp\screenshot.py" -Encoding UTF8
python "C:\tmp\screenshot.py"

Write-Host "=== Setup Complete ==="