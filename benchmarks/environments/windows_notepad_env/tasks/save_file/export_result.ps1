# Export modified sample.txt for verification

$ResultDir = "C:\workspace\results"
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null

$SamplePath = "C:\Users\Docker\Desktop\Tasks\sample.txt"
if (Test-Path $SamplePath) {
    Copy-Item $SamplePath "$ResultDir\result_sample.txt"
    Write-Host "Result exported"
} else {
    Write-Host "sample.txt not found"
}
