# Setup script for configure_production_scanner task
# Sets bcWebCam to starting state: FlipBitmap=False, linear barcodes disabled, ENTER key, 0 grace period

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up configure_production_scanner task ==="

. C:\workspace\scripts\task_utils.ps1

# 1. Kill any existing bcWebCam
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = $prevEAP

# 2. Write the known starting INI (FlipBitmap=False, linear OFF, ENTER key, 0 grace)
$iniDir = "C:\Users\Docker\AppData\Local\bcWebCam"
New-Item -ItemType Directory -Force -Path $iniDir | Out-Null

$iniContent = @"
[General]
Language=en
UpdateCheck=True
AppStartCounter=5
Beep=True
Opacity=0,8
SendKeysPostfix={ENTER}
RecType=3
FlipBitmap=False
DebugDumpImage=
OCR=0
CamUseDefault=False
CamChoosen=
BcGracePeriod=0
TopMost=1
Threshold=0

[FormMain]
Top=50
Left=50
Width=681
Height=598

[BarcodeL]
Type=0

[BarcodeP]
Type=256

[BarcodeD]
Type=0

[BarcodeA]
Type=0

[BarcodePN]
Type=0
Type2=64
"@

Set-Content -Path "$iniDir\bcWebCam.ini" -Value $iniContent -Encoding UTF8
Write-Host "Starting INI written: FlipBitmap=False, BarcodeL=0 (linear OFF), ENTER key, grace=0"

# 3. Record baseline INI for change detection
$baseline = @{
    FlipBitmap      = "False"
    SendKeysPostfix = "{ENTER}"
    BcGracePeriod   = "0"
    BarcodeL_Type   = "0"
}
$baseline | ConvertTo-Json | Set-Content -Path "C:\Windows\Temp\production_scanner_baseline.json" -Encoding UTF8

# 4. Launch bcWebCam in interactive session
$edgeKiller = Start-EdgeKillerTask
Close-Browsers
Launch-BcWebCamInteractive -WaitSeconds 10
Close-Browsers
Start-Sleep -Seconds 3
Dismiss-BcWebCamDialogs -Retries 3 -InitialWaitSeconds 3
Ensure-BcWebCamReady -MaxAttempts 5
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== configure_production_scanner setup complete ==="
