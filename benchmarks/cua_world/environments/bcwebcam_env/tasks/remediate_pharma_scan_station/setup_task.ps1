# Setup script for remediate_pharma_scan_station task
# Writes a misconfigured INI (linear + QR + DataMatrix all wrong),
# places the scan log and medications CSV, then launches bcWebCam.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up remediate_pharma_scan_station task ==="

# ── source shared helpers ────────────────────────────────────────────
. C:\workspace\scripts\task_utils.ps1

# ── 1. Kill any running bcWebCam ─────────────────────────────────────
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = $prevEAP

# ── 2. Write the MISCONFIGURED starting INI ──────────────────────────
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
TopMost=0
Threshold=0
OpenURL=True

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
Write-Host "Starting INI written (misconfigured: linear+QR ON, DataMatrix OFF, Beep ON, etc.)"

# ── 3. Create ScanStation directory and place data files ─────────────
$scanDir = "C:\Users\Docker\Documents\ScanStation"
New-Item -ItemType Directory -Force -Path $scanDir | Out-Null

# Delete stale outputs BEFORE anything else
Remove-Item -Path "$scanDir\audit_report.csv" -Force -ErrorAction SilentlyContinue
Write-Host "Stale audit_report.csv removed (if any)"

# Write the scan log (10 mixed entries from the last 24 hours)
$scanLog = @"
2026-03-20 08:15:23 | (01)00300010633215(17)260531(10)BXL99
2026-03-20 08:22:11 | 5449000000996
2026-03-20 08:31:02 | (01)00357111370104(17)270228(10)ACLOT42
2026-03-20 08:35:18 | https://track.pharma-supplier.com/shipment/RX-20260319
2026-03-20 08:41:55 | (01)00363391312393(17)260930(10)MKB2024
2026-03-20 08:48:07 | 4006381333931
2026-03-20 08:55:41 | (01)00312547698521(17)250115(10)EXP2025
2026-03-20 09:05:28 | (01)00398765432109(17)261130(10)QRS55
2026-03-20 09:12:44 | 7622210449283
2026-03-20 09:18:33 | (01)00346587231092(17)260815(10)NBX77A
"@

Set-Content -Path "$scanDir\scan_log.txt" -Value $scanLog.Trim() -Encoding UTF8
Write-Host "Scan log written: 10 entries (6 DataMatrix, 3 EAN-13, 1 QR URL)"

# Write the approved medications database
$medsCSV = @"
GTIN,ProductName,Manufacturer
00300010633215,Lisinopril 10mg Tablets,Aurobindo Pharma
00357111370104,Metformin HCl 500mg ER,Teva Pharmaceuticals
00363391312393,Omeprazole 20mg DR Capsules,Dr. Reddy's Laboratories
00312547698521,Amoxicillin 250mg Capsules,Sandoz Inc
00346587231092,Atorvastatin 20mg Tablets,Mylan N.V.
"@

Set-Content -Path "$scanDir\approved_medications.csv" -Value $medsCSV.Trim() -Encoding UTF8
Write-Host "Approved medications CSV written: 5 products"

# ── 4. Record task-start timestamp ───────────────────────────────────
$baseline = @{
    task_start = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    ini_hash   = (Get-FileHash "$iniDir\bcWebCam.ini" -Algorithm MD5).Hash
}
$baseline | ConvertTo-Json | Set-Content -Path "C:\Windows\Temp\remediate_pharma_scan_station_baseline.json" -Encoding UTF8
Write-Host "Baseline recorded at $($baseline.task_start)"

# ── 5. Launch bcWebCam in interactive session ────────────────────────
$edgeKiller = Start-EdgeKillerTask
Close-Browsers

Launch-BcWebCamInteractive -WaitSeconds 10
Close-Browsers
Start-Sleep -Seconds 3

Dismiss-BcWebCamDialogs -Retries 3 -InitialWaitSeconds 3
Ensure-BcWebCamReady -MaxAttempts 5

Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== remediate_pharma_scan_station setup complete ==="
