# PowerShell script for exporting results
$ErrorActionPreference = "Continue"
Write-Output "=== Exporting Results ==="

# Define paths
$docPath = "C:\Users\Docker\Documents"
$verifyFile = "$docPath\fd_verification.txt"
$proofImg = "$docPath\fd_association_proof.png"
$startTimeStr = Get-Content "C:\workspace\task_start_time.txt" -ErrorAction SilentlyContinue
if ($startTimeStr) {
    $startTime = [DateTime]::Parse($startTimeStr)
} else {
    $startTime = (Get-Date).AddMinutes(-60) # Fallback
}

# 1. Check Verification Text File
$textFileExists = $false
$textCreatedDuring = $false
$textContent = ""

if (Test-Path $verifyFile) {
    $textFileExists = $true
    $fileInfo = Get-Item $verifyFile
    if ($fileInfo.LastWriteTime -gt $startTime) {
        $textCreatedDuring = $true
    }
    $textContent = Get-Content $verifyFile -Raw
}

# 2. Check Proof Screenshot
$imgFileExists = $false
$imgCreatedDuring = $false
$imgSize = 0

if (Test-Path $proofImg) {
    $imgFileExists = $true
    $fileInfo = Get-Item $proofImg
    $imgSize = $fileInfo.Length
    if ($fileInfo.LastWriteTime -gt $startTime) {
        $imgCreatedDuring = $true
    }
}

# 3. Capture Final Desktop Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
$bitmap.Save("C:\workspace\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

# 4. Create JSON Result
$result = @{
    text_file_exists = $textFileExists
    text_created_during = $textCreatedDuring
    text_content = $textContent
    image_file_exists = $imgFileExists
    image_created_during = $imgCreatedDuring
    image_size_bytes = $imgSize
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$json = $result | ConvertTo-Json -Depth 5
Set-Content -Path "C:\workspace\task_result.json" -Value $json

Write-Output "Result exported to C:\workspace\task_result.json"
Write-Output $json
Write-Output "=== Export Complete ==="