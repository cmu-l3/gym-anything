# PowerShell script saved as setup_task.ps1 in the environment
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up NEC Voltage Drop Task ==="

# Record start time
$startTime = Get-Date
$startTime.ToString("yyyy-MM-dd HH:mm:ss") | Out-File "C:\tmp\task_start_time.txt" -Encoding ascii

# Define paths
$docPath = "C:\Users\Docker\Documents"
$filePath = "$docPath\commercial_circuits.xlsx"

# Ensure directory exists
if (-not (Test-Path $docPath)) {
    New-Item -ItemType Directory -Path $docPath | Out-Null
}

# Remove previous file if exists
if (Test-Path $filePath) {
    Remove-Item $filePath -Force
}

# Create Excel Object
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

$workbook = $excel.Workbooks.Add()

# --- Sheet 2: NEC Table 8 Data ---
$sheet2 = $workbook.Worksheets.Add()
$sheet2.Name = "NEC_Table_8"

# Real NEC Chapter 9 Table 8 Data (partial for common building wire)
$headers2 = @("Size (AWG/kcmil)", "Copper (Ohms/kft)", "Aluminum (Ohms/kft)")
$data2 = @(
    @("14", 3.14, 5.15),
    @("12", 1.98, 3.25),
    @("10", 1.24, 2.03),
    @("8", 0.778, 1.28),
    @("6", 0.491, 0.808),
    @("4", 0.308, 0.508),
    @("3", 0.245, 0.403),
    @("2", 0.194, 0.319),
    @("1", 0.154, 0.253),
    @("1/0", 0.122, 0.201),
    @("2/0", 0.0967, 0.159),
    @("3/0", 0.0766, 0.126),
    @("4/0", 0.0608, 0.100)
)

# Populate Table 8
for ($c = 0; $c -lt $headers2.Count; $c++) {
    $sheet2.Cells.Item(1, $c + 1) = $headers2[$c]
    $sheet2.Cells.Item(1, $c + 1).Font.Bold = $true
}

for ($r = 0; $r -lt $data2.Count; $r++) {
    for ($c = 0; $c -lt $data2[$r].Count; $c++) {
        $sheet2.Cells.Item($r + 2, $c + 1) = $data2[$r][$c]
    }
}
$sheet2.Columns.AutoFit()

# --- Sheet 1: Circuit Schedule ---
$sheet1 = $workbook.Worksheets.Item($workbook.Worksheets.Count) 
$sheet1.Name = "Circuit_Schedule"
$sheet1.Move($workbook.Worksheets.Item(1)) # Move to front

$headers1 = @("Circuit_ID", "Description", "Voltage (V)", "Load (Amps)", "Length (ft)", "Wire Size", "Material", "Resistance (Ohms/kft)", "Voltage Drop (V)", "% Drop", "Status")

for ($c = 0; $c -lt $headers1.Count; $c++) {
    $sheet1.Cells.Item(1, $c + 1) = $headers1[$c]
    $sheet1.Cells.Item(1, $c + 1).Font.Bold = $true
    $sheet1.Cells.Item(1, $c + 1).Interior.ColorIndex = 15 # Grey background
}

# Generate 50 rows of realistic data
$sizes = @("14", "12", "10", "8", "6", "4", "2", "1/0")
$materials = @("Copper", "Copper", "Copper", "Aluminum")
$rnd = New-Object System.Random

for ($i = 2; $i -le 51; $i++) {
    $cid = "CKT-" + (100 + $i - 1)
    
    # Logic for realistic values
    $load = $rnd.Next(5, 50)
    
    if ($load -lt 15) { 
        $desc = "Lighting"
        $volt = 120 
        $sz = "12"
    } elseif ($load -lt 25) { 
        $desc = "Receptacles"
        $volt = 120 
        $sz = "10"
    } else { 
        $desc = "HVAC / Equipment"
        $volt = 208 
        $sz = "8"
    }
    
    # Length: 50ft to 350ft
    $len = $rnd.Next(50, 350)
    
    # Introduce some "Fail" conditions by forcing long lengths or smaller wires
    if ($i % 7 -eq 0) { $len = 400; $sz = "12" } # Guaranteed fail
    
    $mat = $materials[$rnd.Next(0, $materials.Count)]
    
    $sheet1.Cells.Item($i, 1) = $cid
    $sheet1.Cells.Item($i, 2) = $desc
    $sheet1.Cells.Item($i, 3) = $volt
    $sheet1.Cells.Item($i, 4) = $load
    $sheet1.Cells.Item($i, 5) = $len
    $sheet1.Cells.Item($i, 6) = $sz
    $sheet1.Cells.Item($i, 7) = $mat
}

$sheet1.Columns.AutoFit()
$sheet1.Activate()

# Save
$workbook.SaveAs($filePath)
$workbook.Close()
$excel.Quit()

# Release COM objects
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($sheet2) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($sheet1) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Write-Host "File created at $filePath"

# Open Excel for the agent
Start-Process "C:\Program Files\Microsoft Office\Office14\EXCEL.EXE" $filePath
Start-Sleep -Seconds 5

# Maximize Window (using WASP or simple key strokes if available, fallback to just opening)
# In this environment, we assume the window opens visible.

# Take initial screenshot using python tool or similar if available, 
# but here we rely on the framework to capture the state.

Write-Host "=== Setup Complete ==="