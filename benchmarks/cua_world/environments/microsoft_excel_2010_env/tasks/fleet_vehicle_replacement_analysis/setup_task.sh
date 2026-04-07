# Note: This file is named .sh for framework consistency, but strictly contains PowerShell code
# meant to be executed via the 'pre_task' hook command specified in task.json.
# In a real deployment, this would be saved as setup_task.ps1.

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Fleet Analysis Task ==="

# Define paths
$DocPath = "C:\Users\Docker\Documents"
$WorkDir = "C:\workspace\tasks\fleet_vehicle_replacement_analysis"
$ExcelPath = "$DocPath\fleet_analysis.xlsx"
$TimestampFile = "C:\workspace\tasks\fleet_vehicle_replacement_analysis\task_start_time.txt"

# Create directories
if (-not (Test-Path $DocPath)) { New-Item -ItemType Directory -Force -Path $DocPath }
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir }

# Record start time
[int][double]::Parse((Get-Date -UFormat %s)) | Out-File $TimestampFile -Encoding ascii

# -------------------------------------------------------------------------
# GENERATE DATA
# -------------------------------------------------------------------------
# We will generate CSVs first, then convert to XLSX using Excel COM
# This avoids needing Python/Pandas in the Windows container

$InventoryCsv = "$WorkDir\inventory.csv"
$LogCsv = "$WorkDir\log.csv"
$PolicyCsv = "$WorkDir\policy.csv"

# 1. Generate Inventory Data (60 vehicles)
# Mix of old/new, high/low miles to ensure some trigger replacement
$InventoryData = @()
$InventoryData += "VIN,Make,Model,Year,Odometer,Dept,Total Maint Cost,Age,CPM,Status" # Headers

for ($i = 1; $i -le 60; $i++) {
    $Vin = "1FT" + (Get-Random -Min 10000 -Max 99999).ToString() + "X$i"
    $Make = "Ford"
    $Model = "Transit 250"
    
    # Randomize Year (2014-2024)
    # Weight towards newer, but ensure enough old ones
    $Rnd = Get-Random -Min 0 -Max 100
    if ($Rnd -lt 20) { $Year = Get-Random -Min 2014 -Max 2017 } # Old
    else { $Year = Get-Random -Min 2018 -Max 2024 }
    
    # Odometer logic based on age
    $Age = 2025 - $Year
    $OdoBase = $Age * 25000
    $Odo = [math]::Round($OdoBase * ((Get-Random -Min 80 -Max 120) / 100))
    
    # Dept
    $Dept = (Get-Random -InputObject @("Logistics", "Service", "Delivery", "HQ"))
    
    $InventoryData += "$Vin,$Make,$Model,$Year,$Odo,$Dept,,,,"
}
$InventoryData | Out-File $InventoryCsv -Encoding ascii

# 2. Generate Maintenance Log (1200+ rows)
# We need to ensure costs align loosely with age/miles so CPM calculation is interesting
$LogData = @()
$LogData += "Date,VIN,Service_Type,Cost"

# Read back VINs to generate logs for them
$Vins = ($InventoryData | Select-Object -Skip 1) | ForEach-Object { $_.Split(',')[0] }

foreach ($Vin in $Vins) {
    # Determine how "expensive" this car is (some are lemons)
    $IsLemon = (Get-Random -Min 0 -Max 100) -lt 15
    
    $NumServices = Get-Random -Min 10 -Max 30
    for ($j = 0; $j -lt $NumServices; $j++) {
        $Date = (Get-Date).AddDays(-(Get-Random -Min 1 -Max 700)).ToString("yyyy-MM-dd")
        
        $TypeRnd = Get-Random -Min 0 -Max 100
        if ($TypeRnd -lt 60) { 
            $Type = "Oil Change"; $Cost = Get-Random -Min 60 -Max 120 
        } elseif ($TypeRnd -lt 80) { 
            $Type = "Tires"; $Cost = Get-Random -Min 400 -Max 800 
        } elseif ($TypeRnd -lt 95) { 
            $Type = "Brakes"; $Cost = Get-Random -Min 300 -Max 600 
        } else { 
            $Type = "Transmission/Engine"; $Cost = Get-Random -Min 1200 -Max 3500 
        }
        
        if ($IsLemon) { $Cost = [math]::Round($Cost * 2.5) }
        
        $LogData += "$Date,$Vin,$Type,$Cost"
    }
}
$LogData | Out-File $LogCsv -Encoding ascii

# 3. Generate Policy Data
$PolicyData = @()
$PolicyData += "Parameter,Value,Description"
$PolicyData += "Replacement Age,8,Years"
$PolicyData += "Replacement Miles,200000,Miles"
$PolicyData += "High Cost CPM,$0.12,Cost Per Mile"
$PolicyData += "New Vehicle Cost,`$58000,Unit Price"
$PolicyData += "Current Fiscal Year,2025,"
$PolicyData += ",,"
$PolicyData += "TOTAL BUDGET REQUIRED,,<-- Calculate Here"
$PolicyData | Out-File $PolicyCsv -Encoding ascii

# -------------------------------------------------------------------------
# CONVERT TO XLSX VIA COM
# -------------------------------------------------------------------------
Write-Host "Converting CSVs to XLSX..."

# Close Excel if running
Get-Process excel -ErrorAction SilentlyContinue | Stop-Process -Force

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

# Create new workbook
$wb = $excel.Workbooks.Add()

# --- Sheet 3: Policy ---
$ws3 = $wb.Sheets.Add()
$ws3.Name = "Policy"
$qt3 = $ws3.QueryTables.Add("TEXT;$PolicyCsv", $ws3.Range("A1"))
$qt3.TextFileCommaDelimiter = $true
$qt3.Refresh()
$ws3.Columns.AutoFit()

# --- Sheet 2: Maint_Log ---
$ws2 = $wb.Sheets.Add()
$ws2.Name = "Maint_Log"
$qt2 = $ws2.QueryTables.Add("TEXT;$LogCsv", $ws2.Range("A1"))
$qt2.TextFileCommaDelimiter = $true
$qt2.Refresh()
# Format Date column
$ws2.Columns.Item(1).NumberFormat = "yyyy-mm-dd"
$ws2.Columns.AutoFit()

# --- Sheet 1: Inventory ---
$ws1 = $wb.Sheets.Add()
$ws1.Name = "Inventory"
$qt1 = $ws1.QueryTables.Add("TEXT;$InventoryCsv", $ws1.Range("A1"))
$qt1.TextFileCommaDelimiter = $true
$qt1.Refresh()
$ws1.Columns.AutoFit()

# Delete default sheets if any remaining
foreach ($sheet in $wb.Sheets) {
    if ($sheet.Name -match "Sheet") { $sheet.Delete() }
}

# Save
$wb.SaveAs($ExcelPath, 51) # 51 = xlOpenXMLWorkbook (xlsx)
$wb.Close()
$excel.Quit()

# Clean up CSVs
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
Remove-Item $InventoryCsv
Remove-Item $LogCsv
Remove-Item $PolicyCsv

Write-Host "Setup Complete. File saved to $ExcelPath"