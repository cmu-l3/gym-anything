# Note: This is actually a PowerShell script saved as setup_task.ps1 in the environment
# But for the platform generator, we output the content here.
# The hooks in task.json refer to .ps1, so we write this file content to be compatible.

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up AR Aging Task ==="

# 1. timestamp
$startTime = Get-Date -UFormat %s
$startTime | Out-File "C:\Users\Docker\Desktop\task_start_time.txt" -Encoding ASCII

# 2. Create Task Directory
$taskDir = "C:\Users\Docker\Desktop\PowerBITasks"
if (-not (Test-Path -Path $taskDir)) {
    New-Item -ItemType Directory -Path $taskDir | Out-Null
}

# 3. Clean up previous artifacts
if (Test-Path "C:\Users\Docker\Desktop\AR_Aging_Report.pbix") {
    Remove-Item "C:\Users\Docker\Desktop\AR_Aging_Report.pbix" -Force
}

# 4. Generate Realistic Invoice Data using Python
# We use Python here because it's available in the env and easier for generating distribution data than PowerShell
$pythonScript = @"
import pandas as pd
import numpy as np
import datetime
import random

np.random.seed(42)
rows = 2000

# Customers
customers = [f'Customer {c}' for c in ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta', 'Eta', 'Theta', 'Iota', 'Kappa']]
customer_list = np.random.choice(customers, rows)

# Dates (distributed throughout 2024)
base_date = datetime.date(2024, 1, 1)
date_list = [base_date + datetime.timedelta(days=int(x)) for x in np.random.randint(0, 360, rows)]

# Terms & Due Dates
terms = np.random.choice([15, 30, 45, 60], rows)
due_date_list = [d + datetime.timedelta(days=int(t)) for d, t in zip(date_list, terms)]

# Amounts (Log-normal distribution for financial realism)
amounts = np.round(np.random.lognormal(8, 1, rows), 2)

# Status (Paid vs Unpaid)
status_choices = ['Paid', 'Unpaid']
status_weights = [0.6, 0.4]
status_list = np.random.choice(status_choices, rows, p=status_weights)

df = pd.DataFrame({
    'Invoice_ID': range(10001, 10001 + rows),
    'Customer_Name': customer_list,
    'Invoice_Date': date_list,
    'Due_Date': due_date_list,
    'Amount': amounts,
    'Status': status_list
})

df.to_csv(r'C:\Users\Docker\Desktop\PowerBITasks\invoices.csv', index=False)
print('Generated invoices.csv')
"@

$pythonScript | Out-File "$taskDir\generate_data.py" -Encoding ASCII
python "$taskDir\generate_data.py"

# 5. Start Power BI Desktop
Write-Host "Starting Power BI Desktop..."
if (-not (Get-Process PBIDesktop -ErrorAction SilentlyContinue)) {
    Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    
    # Wait for window
    $timeout = 60
    $timer = 0
    while ($timer -lt $timeout) {
        if (Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowTitle -ne ""}) {
            break
        }
        Start-Sleep -Seconds 1
        $timer++
    }
}

# 6. Initial Screenshot (using python/PIL or similar tool if available, otherwise skip)
# The framework handles trajectory screenshots, so this is optional but good practice if tools exist.
# In this windows env, we rely on the framework's VLM recording.

Write-Host "=== Setup Complete ==="