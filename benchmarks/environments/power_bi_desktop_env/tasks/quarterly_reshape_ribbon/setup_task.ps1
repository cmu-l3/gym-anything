# Note: In the Windows environment, this is actually a PowerShell script (setup_task.ps1)
# The framework executes it via: powershell -ExecutionPolicy Bypass -File ...

Write-Host "=== Setting up quarterly_reshape_ribbon task ==="

# 1. Define Paths
$DesktopPath = "C:\Users\Docker\Desktop"
$TaskDir = "$DesktopPath\PowerBITasks\QuarterlyFiles"
$SourceData = "$DesktopPath\PowerBITasks\sales_data.csv"
$StartTimeFile = "C:\Users\Docker\Desktop\task_start_time.txt"

# 2. Record Start Time (Anti-gaming)
$CurrentTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$CurrentTime | Out-File -FilePath $StartTimeFile -Encoding ascii -Force

# 3. Clean previous run artifacts
if (Test-Path "$DesktopPath\Quarterly_Reshaped.pbix") {
    Remove-Item "$DesktopPath\Quarterly_Reshaped.pbix" -Force
}
if (Test-Path $TaskDir) {
    Remove-Item $TaskDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TaskDir | Out-Null

# 4. Generate Wide-Format CSV Data
# We use a Python script embedded in PowerShell to robustly reshape the data
$PythonScript = @"
import pandas as pd
import numpy as np
import os
import random

# Load source data if exists, else create synthetic
source_path = r'$SourceData'
output_dir = r'$TaskDir'

if os.path.exists(source_path):
    df = pd.read_csv(source_path)
else:
    # Fallback synthetic generation (should not happen in this env, but safe)
    data = {
        'Sales_Rep': ['Rep' + str(i) for i in range(1, 20)],
        'Region': ['North', 'South', 'East', 'West'] * 5,
        'Sales_Amount': [random.randint(100, 5000) for _ in range(19)],
        'Product_Category': ['Electronics', 'Clothing', 'Food', 'Furniture'] * 5
    }
    df = pd.DataFrame(data)

# Ensure columns exist
if 'Month' not in df.columns:
    months = ['January', 'February', 'March']
    df['Month'] = np.random.choice(months, size=len(df))

# Process for each month
for month in ['January', 'February', 'March']:
    # Filter or simulate data for this month
    # We take a random sample to make files different sizes
    month_data = df.sample(frac=0.3, random_state=len(month))
    month_data['Month'] = month
    
    # Pivot to wide format: Index=[Sales_Rep, Region, Month], Columns=Product_Category, Values=Sales_Amount
    # Handle duplicates by summing
    pivot_df = month_data.pivot_table(
        index=['Sales_Rep', 'Region', 'Month'], 
        columns='Product_Category', 
        values='Sales_Amount', 
        aggfunc='sum',
        fill_value=0
    ).reset_index()
    
    # Save
    outfile = os.path.join(output_dir, f'sales_{month.lower()}.csv')
    pivot_df.to_csv(outfile, index=False)
    print(f"Created {outfile} with {len(pivot_df)} rows")
"@

# Write Python script to temp file and execute
$ScriptPath = "$env:TEMP\generate_wide_data.py"
$PythonScript | Out-File -FilePath $ScriptPath -Encoding UTF8
python $ScriptPath

# 5. Ensure Power BI is clean
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 6. Start Power BI Desktop
Write-Host "Starting Power BI Desktop..."
Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
Start-Sleep -Seconds 10

# 7. Maximize Window (using WScript.Shell for basic interaction if wmctrl missing on Windows)
$wshell = New-Object -ComObject WScript.Shell
$wshell.AppActivate("Power BI Desktop")
Start-Sleep -Seconds 1
$wshell.SendKeys("% x") # Alt+Space, x (Maximize)

Write-Host "=== Task setup complete ==="