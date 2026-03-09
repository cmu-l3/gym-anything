# Export script for configure_qr_url_audit task
# Kills bcWebCam to flush INI, then reads and exports all relevant settings
# URL open key name candidates are exported individually

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting configure_qr_url_audit result ==="

. C:\workspace\scripts\task_utils.ps1

# 1. Kill bcWebCam to force INI flush to disk
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 2. Take final screenshot
try {
    Invoke-PyAutoGUICommand -Command @{action="screenshot"; path="C:\Windows\Temp\qr_url_audit_final.png"} -ErrorAction SilentlyContinue
} catch {}

# 3. Read the INI file
$iniPath = Get-BcWebCamIniPath
$ini = Read-IniFile -Path $iniPath

# 4. Extract relevant settings
$generalSection = if ($ini.ContainsKey("General")) { $ini["General"] } else { @{} }
$barcodeLSection = if ($ini.ContainsKey("BarcodeL")) { $ini["BarcodeL"] } else { @{} }
$barcodePSection = if ($ini.ContainsKey("BarcodeP")) { $ini["BarcodeP"] } else { @{} }
$barcodeDSection = if ($ini.ContainsKey("BarcodeD")) { $ini["BarcodeD"] } else { @{} }

# Helpers to safely read a key from a section
function Get-Key($section, $key) {
    if ($section.ContainsKey($key)) { return $section[$key] } else { return "" }
}

# 5. Build result JSON manually to avoid nested hashtable serialization issues
$task      = "configure_qr_url_audit"
$ts        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$ini_ex    = (Test-Path $iniPath).ToString().ToLower()   # "true" or "false"

$skp       = Get-Key $generalSection "SendKeysPostfix"
$grace     = Get-Key $generalSection "BcGracePeriod"
$opacity   = Get-Key $generalSection "Opacity"
$beep      = Get-Key $generalSection "Beep"
$flip      = Get-Key $generalSection "FlipBitmap"
$topmost   = Get-Key $generalSection "TopMost"

# All known URL-open key name candidates
$openURL          = Get-Key $generalSection "OpenURL"
$openDetectedURL  = Get-Key $generalSection "OpenDetectedURL"
$openDetectedUrl  = Get-Key $generalSection "OpenDetectedUrl"
$urlOpen          = Get-Key $generalSection "UrlOpen"
$openUrl          = Get-Key $generalSection "OpenUrl"
$openLink         = Get-Key $generalSection "OpenLink"
$autoURL          = Get-Key $generalSection "AutoURL"

$blType = Get-Key $barcodeLSection "Type"
$bpType = Get-Key $barcodePSection "Type"
$bdType = Get-Key $barcodeDSection "Type"

# Escape strings for JSON
function Esc($s) { $s -replace '\\','\\' -replace '"','\"' }

$json = @"
{
  "task": "$(Esc $task)",
  "timestamp": "$(Esc $ts)",
  "ini_exists": $ini_ex,
  "ini_path": "$(Esc $iniPath)",
  "general": {
    "SendKeysPostfix": "$(Esc $skp)",
    "BcGracePeriod": "$(Esc $grace)",
    "Opacity": "$(Esc $opacity)",
    "Beep": "$(Esc $beep)",
    "FlipBitmap": "$(Esc $flip)",
    "TopMost": "$(Esc $topmost)",
    "OpenURL": "$(Esc $openURL)",
    "OpenDetectedURL": "$(Esc $openDetectedURL)",
    "OpenDetectedUrl": "$(Esc $openDetectedUrl)",
    "UrlOpen": "$(Esc $urlOpen)",
    "OpenUrl": "$(Esc $openUrl)",
    "OpenLink": "$(Esc $openLink)",
    "AutoURL": "$(Esc $autoURL)"
  },
  "barcode_l_type": "$(Esc $blType)",
  "barcode_p_type": "$(Esc $bpType)",
  "barcode_d_type": "$(Esc $bdType)"
}
"@

# 6. Save to JSON
$resultPath = "C:\Windows\Temp\configure_qr_url_audit_result.json"
[System.IO.File]::WriteAllText($resultPath, $json, [System.Text.Encoding]::UTF8)
Write-Host "Result JSON written to: $resultPath"

# 7. Display summary for debugging
Write-Host "Beep: $beep"
Write-Host "Opacity: $opacity"
Write-Host "SendKeysPostfix: $skp"
Write-Host "BarcodeL Type: $blType"
Write-Host "OpenURL (candidate): $openURL"
Write-Host "OpenDetectedURL (candidate): $openDetectedURL"

Write-Host "=== Export Complete ==="
