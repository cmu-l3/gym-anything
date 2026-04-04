# Note: In the Windows environment, this is actually a PowerShell script (export_result.ps1)

Write-Host "=== Exporting quarterly_reshape_ribbon result ==="

# 1. Define Paths
$DesktopPath = "C:\Users\Docker\Desktop"
$PBIXFile = "$DesktopPath\Quarterly_Reshaped.pbix"
$ResultFile = "$DesktopPath\reshape_result.json"
$StartTimeFile = "$DesktopPath\task_start_time.txt"
$TempDir = "$env:TEMP\pbi_verify"

# 2. Get Task Start Time
if (Test-Path $StartTimeFile) {
    $TaskStartTime = Get-Content $StartTimeFile
} else {
    $TaskStartTime = 0
}

# 3. Check File Existence & Timestamp
$FileExists = $false
$FileCreatedDuringTask = $false
$FileSize = 0

if (Test-Path $PBIXFile) {
    $FileExists = $true
    $Item = Get-Item $PBIXFile
    $FileSize = $Item.Length
    $CreationTime = $Item.CreationTime.ToUnixTimeSeconds()
    $LastWriteTime = $Item.LastWriteTime.ToUnixTimeSeconds()
    
    if ($LastWriteTime -gt $TaskStartTime) {
        $FileCreatedDuringTask = $true
    }
}

# 4. Stop Power BI to release file lock
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 5. Extract PBIX (It's a ZIP)
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$VisualTypes = @()
$MashupCode = ""

if ($FileExists) {
    try {
        Expand-Archive -Path $PBIXFile -DestinationPath $TempDir -Force
        
        # 5a. Analyze Report Layout (JSON) for Visuals
        $LayoutPath = "$TempDir\Report\Layout"
        if (Test-Path $LayoutPath) {
            # Layout is often UTF-16 LE
            $LayoutContent = Get-Content $LayoutPath -Raw -Encoding Unicode
            # Simple regex extraction for visual types to avoid complex JSON parsing dependencies in shell
            # Matches "visualType":"<type>"
            $Matches = [regex]::Matches($LayoutContent, '"visualType":"([^"]+)"')
            foreach ($match in $Matches) {
                $VisualTypes += $match.Groups[1].Value
            }
        }
        
        # 5b. Analyze DataMashup (Binary) for M Code Keywords
        # We assume if the binary contains the strings, the transform was likely used.
        $MashupPath = "$TempDir\DataMashup"
        if (Test-Path $MashupPath) {
            # Read binary as string (lossy is fine for keyword search)
            $Bytes = [System.IO.File]::ReadAllBytes($MashupPath)
            $StringData = [System.Text.Encoding]::ASCII.GetString($Bytes)
            
            # Search for Power Query M keywords
            if ($StringData -match "Table.Combine" -or $StringData -match "Appended Query") {
                $MashupCode += "Append_Detected "
            }
            if ($StringData -match "Table.Unpivot" -or $StringData -match "UnpivotOtherColumns") {
                $MashupCode += "Unpivot_Detected "
            }
        }
    } catch {
        Write-Host "Error parsing PBIX: $_"
    }
}

# 6. Create JSON Result
$ResultObject = @{
    file_exists = $FileExists
    file_created_during_task = $FileCreatedDuringTask
    file_size_bytes = $FileSize
    visual_types = $VisualTypes
    mashup_indicators = $MashupCode
    timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

$JsonResult = $ResultObject | ConvertTo-Json
$JsonResult | Out-File -FilePath $ResultFile -Encoding UTF8

Write-Host "Result saved to $ResultFile"
Write-Host $JsonResult
Write-Host "=== Export complete ==="