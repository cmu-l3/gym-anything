# Export script for ELISA task
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting ELISA Result ==="

$ResultPath = "C:\Users\Docker\Desktop\ExcelTasks\elisa_data.xlsx"
$JsonPath = "C:\Users\Docker\AppData\Local\Temp\task_result.json"
$ScreenshotPath = "C:\Users\Docker\AppData\Local\Temp\task_final.png"

# Check if file exists and get stats
$Exists = Test-Path $ResultPath
$FileSize = 0
$IsNew = $false

if ($Exists) {
    $Item = Get-Item $ResultPath
    $FileSize = $Item.Length
    $LastWrite = $Item.LastWriteTime.ToFileTime()
    
    # Check start time
    $StartTimeFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"
    if (Test-Path $StartTimeFile) {
        $StartUnix = [double](Get-Content $StartTimeFile)
        # Convert FileTime to Unix
        $LastWriteUnix = ($Item.LastWriteTime.ToUniversalTime() - (Get-Date "1970-01-01 00:00:00Z")).TotalSeconds
        if ($LastWriteUnix -gt $StartUnix) {
            $IsNew = $true
        }
    }
}

# Capture Screenshot (using .NET classes)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Location, [System.Drawing.Point]::Empty, $Screen.Size)
$Bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$Graphics.Dispose()
$Bitmap.Dispose()

# Create JSON result
$Result = @{
    "xlsx_file" = @{
        "exists" = $Exists
        "size" = $FileSize
        "is_new" = $IsNew
        "path" = $ResultPath
    }
    "screenshot_path" = $ScreenshotPath
    "timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$Result | ConvertTo-Json | Out-File $JsonPath -Encoding ascii

Write-Host "Result exported to $JsonPath"
Get-Content $JsonPath