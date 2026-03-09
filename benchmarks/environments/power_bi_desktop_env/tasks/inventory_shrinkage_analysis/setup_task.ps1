# Note: This is a PowerShell script saved with .ps1 extension in the environment,
# but displayed here as shell for syntax highlighting if needed.
# Real filename: setup_task.ps1

Write-Host "=== Setting up Inventory Shrinkage Analysis Task ==="

# 1. Define paths
$desktopPath = "C:\Users\Docker\Desktop"
$taskDir = "$desktopPath\PowerBITasks"
$csvPath = "$taskDir\inventory_audit.csv"
$startTimePath = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# 2. Create directory
if (-not (Test-Path -Path $taskDir)) {
    New-Item -ItemType Directory -Path $taskDir | Out-Null
}

# 3. Clean up previous artifacts
Remove-Item -Path "$desktopPath\Shrinkage_Report.pbix" -ErrorAction SilentlyContinue
Remove-Item -Path "$desktopPath\worst_stores.csv" -ErrorAction SilentlyContinue
Remove-Item -Path $csvPath -ErrorAction SilentlyContinue

# 4. Generate Realistic Data using Python
# We embed a python script to generate correlation and specific loss patterns
$pythonScript = @"
import pandas as pd
import numpy as np
import random

random.seed(42)
np.random.seed(42)

rows = 500
stores = [f'S-{i:03d}' for i in range(1, 21)]
sizes = {s: np.random.randint(2000, 15000) for s in stores}
categories = ['Electronics', 'Clothing', 'Home', 'Groceries', 'Toys']

data = []
for i in range(rows):
    store = random.choice(stores)
    sku = f'SKU-{random.randint(1000, 9999)}'
    cat = random.choice(categories)
    
    # Cost varies by category
    base_cost = {'Electronics': 200, 'Clothing': 40, 'Home': 80, 'Groceries': 10, 'Toys': 30}[cat]
    unit_cost = round(np.random.normal(base_cost, base_cost * 0.2), 2)
    
    system_qty = np.random.randint(10, 100)
    
    # Generate variance (shrinkage vs overage)
    # Skew towards negative (shrinkage)
    if random.random() < 0.7:
        # Loss
        diff = -1 * np.random.randint(1, 5)
    else:
        # Overage or exact
        diff = np.random.randint(0, 3)
        
    physical_qty = max(0, system_qty + diff)
    
    data.append([
        i + 1,
        store,
        sizes[store],
        sku,
        cat,
        unit_cost,
        system_qty,
        physical_qty
    ])

df = pd.DataFrame(data, columns=['Audit_ID', 'Store_ID', 'Store_Size_SqFt', 'Product_SKU', 'Category', 'Unit_Cost', 'System_Qty', 'Physical_Qty'])
df.to_csv(r'$csvPath', index=False)
print('CSV generated successfully')
"@

# Execute Python to generate data
python -c $pythonScript

# 5. Record start time
$timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
Set-Content -Path $startTimePath -Value $timestamp

# 6. Start Power BI Desktop
$pbiProcess = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
if (-not $pbiProcess) {
    Write-Host "Starting Power BI Desktop..."
    Start-Process -FilePath "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    
    # Wait for window
    $timeout = 60
    $timer = 0
    while ($timer -lt $timeout) {
        $w = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
        if ($w -and $w.MainWindowTitle) {
            break
        }
        Start-Sleep -Seconds 1
        $timer++
    }
}

# 7. Maximize Window (using a helper script or simple powershell approach if possible, 
# typically handled by the environment agent, but good to ensure focus)
Write-Host "Setup Complete."