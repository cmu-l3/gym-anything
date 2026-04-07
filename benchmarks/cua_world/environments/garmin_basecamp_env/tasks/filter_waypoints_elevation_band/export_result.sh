#!/bin/bash
echo "=== Exporting Task Results ==="

cat << 'EOF' > C:\export_result.ps1
$ErrorActionPreference = 'SilentlyContinue'

# 1. Verification Variables
$outputFile = "C:\workspace\output\mid_elevation_sightings.gpx"
$fileExists = Test-Path $outputFile
$createdDuringTask = $false
$fileSize = 0

# 2. Check File State and Integrity (Anti-Gaming)
if ($fileExists) {
    $fileInfo = Get-Item $outputFile
    $fileSize = $fileInfo.Length
    $mtime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime.ToUniversalTime() -UFormat %s))
    
    $startTime = 0
    if (Test-Path "C:\task_start_time.txt") {
        $startTime = [int](Get-Content "C:\task_start_time.txt" -Raw)
    }
    
    if ($mtime -ge $startTime) {
        $createdDuringTask = $true
    }
}

# 3. Final State Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.X, $screen.Y, 0, 0, $bitmap.Size)
$bitmap.Save("C:\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

# 4. Process State
$bcRunning = $false
if (Get-Process -Name "BaseCamp" -ErrorAction SilentlyContinue) {
    $bcRunning = $true
}

# 5. Export configuration for Verifier
$result = @{
    output_exists = $fileExists
    file_created_during_task = $createdDuringTask
    output_size_bytes = $fileSize
    app_was_running = $bcRunning
    screenshot_path = "C:\task_final.png"
}

$result | ConvertTo-Json | Out-File -FilePath "C:\task_result.json" -Encoding utf8
EOF

powershell.exe -ExecutionPolicy Bypass -File C:\export_result.ps1

echo "Result saved. Outputting payload:"
cat C:/task_result.json 2>/dev/null || cat C:\\task_result.json 2>/dev/null
echo "=== Export complete ==="