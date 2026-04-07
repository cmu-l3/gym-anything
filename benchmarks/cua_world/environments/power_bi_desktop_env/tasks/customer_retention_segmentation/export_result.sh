# Export script for Customer Retention Segmentation task (PowerShell)
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

# Define paths
$DesktopPath = "C:\Users\Docker\Desktop"
$PBIXFile = "$DesktopPath\Customer_Retention.pbix"
$CSVFile = "$DesktopPath\lost_customers.csv"
$ResultFile = "$DesktopPath\customer_retention_result.json"
$TempDir = "$DesktopPath\PBIX_Extract"

# Get Task Start Time
if (Test-Path "$DesktopPath\task_start_time.txt") {
    $TaskStart = Get-Content "$DesktopPath\task_start_time.txt"
} else {
    $TaskStart = 0
}
$TaskEnd = [DateTimeOffset]::Now.ToUnixTimeSeconds()

# 1. Close Power BI to release file locks
Stop-Process -Name "PBIDesktop" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Check File Existence and Metadata
$PBIXExists = Test-Path $PBIXFile
$CSVExists = Test-Path $CSVFile
$FileSize = 0
$FileCreatedDuringTask = $false

if ($PBIXExists) {
    $Item = Get-Item $PBIXFile
    $FileSize = $Item.Length
    
    # Check creation time (Unix timestamp comparison)
    $CreationTime = [DateTimeOffset]::new($Item.CreationTime).ToUnixTimeSeconds()
    $LastWriteTime = [DateTimeOffset]::new($Item.LastWriteTime).ToUnixTimeSeconds()
    
    if ($LastWriteTime -ge $TaskStart) {
        $FileCreatedDuringTask = $true
    }
}

# 3. Analyze PBIX Internal Structure (Verification of Logic)
$HasTable = $false
$HasRecency = $false
$HasStatus = $false
$HasDonut = $false
$HasTableVisual = $false

if ($PBIXExists) {
    # Prepare extraction directory
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $TempDir | Out-Null
    
    # Rename to .zip and extract
    $ZipPath = "$TempDir\report.zip"
    Copy-Item $PBIXFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force
    
    # A. Check Visuals in Layout
    $LayoutPath = "$TempDir\Report\Layout"
    if (Test-Path $LayoutPath) {
        # Layout is often JSON-like but encoded. We search for raw strings.
        # This is a heuristic scan.
        $LayoutContent = Get-Content $LayoutPath -Raw
        
        # Check for visual types
        if ($LayoutContent -match "donutChart") { $HasDonut = $true }
        if ($LayoutContent -match "tableEx" -or $LayoutContent -match "pivotTable") { $HasTableVisual = $true }
    }
    
    # B. Check Data Model (DataModel file is binary, but strings are visible)
    $ModelPath = "$TempDir\DataModel"
    if (Test-Path $ModelPath) {
        # Read as binary strings (simple grep equivalent)
        $ModelBytes = Get-Content $ModelPath -Encoding Byte -ReadCount 0
        $ModelString = [System.Text.Encoding]::ASCII.GetString($ModelBytes)
        
        # Check for calculated table and column names
        if ($ModelString -match "Customer_Profiles") { $HasTable = $true }
        if ($ModelString -match "Recency_Days") { $HasRecency = $true }
        if ($ModelString -match "Status") { $HasStatus = $true }
    }
    
    # Cleanup
    Remove-Item $TempDir -Recurse -Force
}

# 4. Analyze CSV Content (Verification of Export)
$CSVValid = $false
$CSVRowCount = 0
$RecencyCheck = $true # Will set to false if we find bad data

if ($CSVExists) {
    $CsvContent = Import-Csv $CSVFile
    $CSVRowCount = $CsvContent.Count
    
    if ($CSVRowCount -gt 0) {
        $CSVValid = $true
        
        # Verify columns exist
        $Cols = $CsvContent[0].PSObject.Properties.Name
        if (-not ($Cols -contains "Recency_Days" -or $Cols -contains "Status")) {
            $RecencyCheck = $false
        }
        
        # Verify filtering logic (Recency > 270 for 'Lost')
        # We sample a few rows to check
        foreach ($row in $CsvContent) {
            if ($row.Recency_Days) {
                try {
                    $val = [int]$row.Recency_Days
                    if ($val -le 270) { $RecencyCheck = $false; break }
                } catch {
                    # Ignore parsing errors
                }
            }
        }
    }
}

# 5. Create Result JSON
$Result = @{
    pbix_exists = $PBIXExists
    pbix_size_bytes = $FileSize
    created_during_task = $FileCreatedDuringTask
    has_customer_profiles_table = $HasTable
    has_recency_column = $HasRecency
    has_status_column = $HasStatus
    has_donut_visual = $HasDonut
    has_table_visual = $HasTableVisual
    csv_exists = $CSVExists
    csv_row_count = $CSVRowCount
    csv_logic_correct = $RecencyCheck
    timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
}

$Result | ConvertTo-Json -Depth 5 | Out-File $ResultFile -Encoding UTF8

Write-Host "Result exported to $ResultFile"
Get-Content $ResultFile
Write-Host "=== Export Complete ==="