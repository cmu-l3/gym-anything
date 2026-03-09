# Export document.txt for verification

$ResultDir = "C:\workspace\results"
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null

$DocPath = "C:\Users\Docker\Desktop\Tasks\document.txt"
if (Test-Path $DocPath) {
    Copy-Item $DocPath "$ResultDir\result_document.txt"
    Write-Host "Result exported"
}
