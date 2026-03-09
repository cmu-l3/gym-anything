# Note: This is actually a PowerShell script (setup_task.ps1) as specified in task.json hooks
# But we follow the framework convention of providing the content. 
# The environment uses PowerShell for Windows hooks.

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Smart Home Telemetry ETL Task ==="

# 1. Create Task Directory
$TaskDir = "C:\Users\Docker\Desktop\PowerBITasks"
if (-not (Test-Path $TaskDir)) {
    New-Item -ItemType Directory -Force -Path $TaskDir | Out-Null
}

# 2. Generate JSON Data using Python
# We use python inside the Windows VM to generate the JSON
$JsonGenScript = @"
import json
import random
import datetime

data = []
# Fixed start time for reproducibility
start_time = datetime.datetime(2023, 10, 1, 0, 0, 0)

# Generate 5 homes
for h in range(1, 6):
    home = {
        'home_id': f'H{h:03}', 
        'address': f'{random.randint(100,999)} Main St',
        'devices': []
    }
    # Generate 3 devices per home
    for d in range(1, 4):
        dev_id = f'D{h}{d}'
        readings = []
        base_temp = 20 + random.uniform(-2, 2)
        
        # Generate 24 hourly readings
        for t in range(24):
            ts = start_time + datetime.timedelta(hours=t)
            # Cycle: cooler at night, warmer in day
            hour_mod = -2 if (t < 6 or t > 20) else 2
            temp = base_temp + hour_mod + random.uniform(-0.5, 0.5)
            
            reading = {
                'timestamp': ts.isoformat(),
                'temperature': round(temp, 1),
                'humidity': round(random.uniform(30, 60), 1),
                'status': 'ok'
            }
            readings.append(reading)
            
        home['devices'].append({
            'device_id': dev_id, 
            'type': 'Thermostat', 
            'model': 'Gen3',
            'readings': readings
        })
    data.append(home)

with open(r'C:\Users\Docker\Desktop\PowerBITasks\device_logs.json', 'w') as f:
    json.dump(data, f, indent=2)
print('JSON data generated successfully')
"@

$GenScriptPath = "$env:TEMP\gen_data.py"
Set-Content -Path $GenScriptPath -Value $JsonGenScript
python $GenScriptPath

# 3. Timestamp for anti-gaming
$StartTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
Set-Content -Path "$env:TEMP\task_start_time.txt" -Value $StartTime

# 4. Clean up previous output
$TargetFile = "C:\Users\Docker\Desktop\Smart_Home_Report.pbix"
if (Test-Path $TargetFile) {
    Remove-Item $TargetFile -Force
}

# 5. Ensure Power BI is ready (Close if open to ensure clean start, or ensure open blank)
# For this task, we want a blank state.
Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Start Power BI Desktop
Write-Host "Starting Power BI Desktop..."
Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
# Wait loop
for ($i=0; $i -lt 60; $i++) {
    if (Get-Process "PBIDesktop" -ErrorAction SilentlyContinue) {
        if (Get-Process "PBIDesktop" | Where-Object {$_.MainWindowTitle -ne ""}) {
            break
        }
    }
    Start-Sleep -Seconds 1
}

# Maximize window (using nircmd or similar if available, else powershell approach)
# Simplest PS way to maximize:
$code = @"
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
"@
try {
    $type = Add-Type -MemberDefinition $code -Name "Win32Maximize" -Namespace Win32Functions -PassThru
    $proc = Get-Process "PBIDesktop" | Sort-Object StartTime -Descending | Select-Object -First 1
    if ($proc) {
        $type::ShowWindow($proc.MainWindowHandle, 3) # 3 = SW_MAXIMIZE
        $type::SetForegroundWindow($proc.MainWindowHandle)
    }
} catch {
    Write-Warning "Could not maximize window programmatically"
}

# Dismiss startup screen if possible (ESC key)
Start-Sleep -Seconds 5
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")

# Take initial screenshot using Python (standard env tool)
python -c "import pyautogui; pyautogui.screenshot(r'C:\Windows\Temp\task_initial.png')"

Write-Host "=== Setup Complete ==="