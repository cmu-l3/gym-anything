# Setup script for configure_qr_url_audit task
# Sets bcWebCam to starting state: URL disabled, beep on, ENTER key, 80% opacity, linear barcodes enabled

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up configure_qr_url_audit task ==="

. C:\workspace\scripts\task_utils.ps1

# 1. Kill any existing bcWebCam
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = $prevEAP

# 2. Write the known starting INI (URL disabled, beep on, ENTER key, 80% opacity, linear barcodes enabled)
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
OpenURL=False

[FormMain]
Top=50
Left=50
Width=681
Height=598

[BarcodeL]
Type=8416887

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
Write-Host "Starting INI written: OpenURL=False, Beep=True, ENTER key, opacity=0,8, BarcodeL=8416887 (linear ON)"

# 3. Record baseline INI for change detection
$baseline = @{
    OpenURL         = "False"
    Beep            = "True"
    SendKeysPostfix = "{ENTER}"
    Opacity         = "0,8"
    BarcodeL_Type   = "8416887"
}
$baseline | ConvertTo-Json | Set-Content -Path "C:\Windows\Temp\qr_url_audit_baseline.json" -Encoding UTF8

# 4. Launch bcWebCam in interactive session
$edgeKiller = Start-EdgeKillerTask
Close-Browsers
Launch-BcWebCamInteractive -WaitSeconds 10
Close-Browsers
Start-Sleep -Seconds 3
Dismiss-BcWebCamDialogs -Retries 3 -InitialWaitSeconds 3
Ensure-BcWebCamReady -MaxAttempts 5
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== configure_qr_url_audit setup complete ==="
