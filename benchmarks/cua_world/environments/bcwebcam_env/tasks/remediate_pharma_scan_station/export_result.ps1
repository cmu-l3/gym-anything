# Export result script for remediate_pharma_scan_station task
# Kills bcWebCam to flush INI, reads back all state, writes JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

. C:\workspace\scripts\task_utils.ps1

Write-Host "=== Exporting remediate_pharma_scan_station results ==="

# ── 1. Kill bcWebCam to force INI flush ──────────────────────────────
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# ── 2. Take final screenshot ─────────────────────────────────────────
try {
    Invoke-PyAutoGUICommand -Command @{
        action = "screenshot"
        path   = "C:\Windows\Temp\remediate_pharma_scan_station_final.png"
    } -ErrorAction SilentlyContinue
} catch {}

# ── 3. Read the INI file ─────────────────────────────────────────────
$iniPath = Get-BcWebCamIniPath
$iniExists = Test-Path $iniPath
$ini = @{}
if ($iniExists) {
    $ini = Read-IniFile -Path $iniPath
}

$generalSection  = if ($ini.ContainsKey("General"))  { $ini["General"]  } else { @{} }
$barcodeLSection = if ($ini.ContainsKey("BarcodeL")) { $ini["BarcodeL"] } else { @{} }
$barcodePSection = if ($ini.ContainsKey("BarcodeP")) { $ini["BarcodeP"] } else { @{} }
$barcodeDSection = if ($ini.ContainsKey("BarcodeD")) { $ini["BarcodeD"] } else { @{} }
$barcodeASection = if ($ini.ContainsKey("BarcodeA")) { $ini["BarcodeA"] } else { @{} }
$barcodePNSection = if ($ini.ContainsKey("BarcodePN")) { $ini["BarcodePN"] } else { @{} }

# ── 4. Read audit report CSV if it exists ────────────────────────────
$auditPath = "C:\Users\Docker\Documents\ScanStation\audit_report.csv"
$auditExists = Test-Path $auditPath
$auditContent = ""
$auditSize = 0
$auditLineCount = 0
$auditModified = ""

if ($auditExists) {
    $auditContent = Get-Content -Path $auditPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $auditContent) { $auditContent = "" }
    $auditSize = (Get-Item $auditPath).Length
    $auditLineCount = (Get-Content -Path $auditPath -ErrorAction SilentlyContinue | Measure-Object).Count
    $auditModified = (Get-Item $auditPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

# ── 5. Check data files still present ────────────────────────────────
$scanLogExists = Test-Path "C:\Users\Docker\Documents\ScanStation\scan_log.txt"
$medsCSVExists = Test-Path "C:\Users\Docker\Documents\ScanStation\approved_medications.csv"

# ── 6. Read baseline timestamp ───────────────────────────────────────
$baselinePath = "C:\Windows\Temp\remediate_pharma_scan_station_baseline.json"
$taskStart = ""
if (Test-Path $baselinePath) {
    try {
        $bl = Get-Content $baselinePath -Raw | ConvertFrom-Json
        $taskStart = $bl.task_start
    } catch {}
}

# ── 7. Build and write result JSON ───────────────────────────────────
# Use manual JSON building to handle all escaping reliably
function Esc([string]$s) {
    if ($null -eq $s) { return "" }
    $s.Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r').Replace("`t",'\t')
}

function GetKey($section, [string]$key) {
    if ($null -eq $section) { return "" }
    if ($section.ContainsKey($key)) {
        $v = $section[$key]
        if ($null -eq $v) { return "" }
        return [string]$v
    }
    return ""
}

$resultPath = "C:\Windows\Temp\remediate_pharma_scan_station_result.json"

$json = @"
{
  "task": "remediate_pharma_scan_station",
  "timestamp": "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "task_start": "$(Esc $taskStart)",
  "ini_exists": $($iniExists.ToString().ToLower()),
  "ini_path": "$(Esc $iniPath)",
  "general": {
    "Beep": "$(Esc (GetKey $generalSection 'Beep'))",
    "Opacity": "$(Esc (GetKey $generalSection 'Opacity'))",
    "SendKeysPostfix": "$(Esc (GetKey $generalSection 'SendKeysPostfix'))",
    "BcGracePeriod": "$(Esc (GetKey $generalSection 'BcGracePeriod'))",
    "TopMost": "$(Esc (GetKey $generalSection 'TopMost'))",
    "FlipBitmap": "$(Esc (GetKey $generalSection 'FlipBitmap'))",
    "OpenURL": "$(Esc (GetKey $generalSection 'OpenURL'))"
  },
  "barcode_l_type": "$(Esc (GetKey $barcodeLSection 'Type'))",
  "barcode_p_type": "$(Esc (GetKey $barcodePSection 'Type'))",
  "barcode_d_type": "$(Esc (GetKey $barcodeDSection 'Type'))",
  "barcode_a_type": "$(Esc (GetKey $barcodeASection 'Type'))",
  "barcode_pn_type": "$(Esc (GetKey $barcodePNSection 'Type'))",
  "audit_report_exists": $($auditExists.ToString().ToLower()),
  "audit_report_path": "$(Esc $auditPath)",
  "audit_report_size": $auditSize,
  "audit_report_line_count": $auditLineCount,
  "audit_report_modified": "$(Esc $auditModified)",
  "audit_report_content": "$(Esc $auditContent)",
  "scan_log_exists": $($scanLogExists.ToString().ToLower()),
  "medications_csv_exists": $($medsCSVExists.ToString().ToLower())
}
"@

[System.IO.File]::WriteAllText($resultPath, $json, [System.Text.Encoding]::UTF8)

Write-Host "Result JSON written to $resultPath"
Write-Host "  INI exists: $iniExists"
Write-Host "  Audit report exists: $auditExists ($auditLineCount lines)"
Write-Host "  Scan log exists: $scanLogExists"
Write-Host "  Medications CSV exists: $medsCSVExists"

Write-Host "=== Export complete ==="
