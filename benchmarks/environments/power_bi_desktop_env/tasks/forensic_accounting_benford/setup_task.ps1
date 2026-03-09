# Note: In the Power BI environment, the hook is defined as a PowerShell script in task.json
# but the content here is provided as a reference/wrapper if needed. 
# However, since the environment uses Windows, I will provide the .ps1 content 
# that should be saved as setup_task.ps1.

# <file name="setup_task.ps1">
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Forensic Accounting Task ==="

# 1. Create Timestamp
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File "C:\workspace\tasks\forensic_accounting_benford\task_start_time.txt" -Encoding ascii

# 2. Prepare Data Directory
$dataDir = "C:\Users\Docker\Desktop\PowerBITasks"
if (!(Test-Path -Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
}

# 3. Generate Realistic Vendor Payment Data (Python)
# We use Python to generate data following Benford's law to make it realistic
$pythonScript = @"
import csv
import random
import math

# Benford's Law Cumulative Distribution Function
def get_benford_digit():
    # P(d) = log10(1 + 1/d)
    # Inverse CDF method roughly: 10^u - 1 where u in [0,1] gives leading digits distributed mostly like Benford
    # But simpler: generate number 10^(random*power)
    val = 10 ** (random.uniform(2, 5)) # Amounts between 100 and 100,000
    return val

def format_currency(val):
    return '${:,.2f}'.format(val)

rows = []
vendors = ['Acme Corp', 'Globex', 'Soylent Corp', 'Initech', 'Umbrella Corp', 'Stark Ind', 'Wayne Ent']
depts = ['IT', 'HR', 'Public Works', 'Sanitation', 'Legal']

# Generate 500 rows
for i in range(500):
    amount = get_benford_digit()
    
    # Introduce some anomalies (fraud!) in Sanitation dept (excess of 9s)
    dept = random.choice(depts)
    if dept == 'Sanitation' and random.random() < 0.3:
        # Fraud padding: amounts starting with 9
        amount = random.uniform(9000, 9999)

    row = {
        'VOUCHER_NUMBER': f'V-{10000+i}',
        'PAYMENT_DATE': f'2023-{random.randint(1,12):02d}-{random.randint(1,28):02d}',
        'VENDOR_NAME': random.choice(vendors),
        'DEPARTMENT': dept,
        'AMOUNT': format_currency(amount) # Dirty text format
    }
    rows.append(row)

with open(r'C:\Users\Docker\Desktop\PowerBITasks\vendor_payments.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['VOUCHER_NUMBER', 'PAYMENT_DATE', 'VENDOR_NAME', 'DEPARTMENT', 'AMOUNT'])
    writer.writeheader()
    writer.writerows(rows)
"@

$pythonScript | Out-File "$dataDir\generate_data.py" -Encoding ascii
python "$dataDir\generate_data.py"

# 4. Clean up previous results
$outputFile = "C:\Users\Docker\Desktop\Fraud_Detection.pbix"
if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}

# 5. Start Power BI Desktop (Optional, but good for visibility)
# We kill existing instances first to ensure a clean slate
Stop-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue

Write-Host "Starting Power BI Desktop..."
Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe" -WindowStyle Maximized

# Wait for process
Start-Sleep -Seconds 10

Write-Host "=== Setup Complete ==="
# </file>