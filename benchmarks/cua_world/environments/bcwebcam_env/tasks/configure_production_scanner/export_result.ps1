# Export script for configure_production_scanner task
# Kills bcWebCam to flush INI, then reads and exports settings

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting configure_production_scanner result ==="

. C:\workspace\scripts\task_utils.ps1

# 1. Kill bcWebCam to force INI flush to disk
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 2. Take final screenshot
try {
    Invoke-PyAutoGUICommand -Command @{action="screenshot"; path="C:\Windows\Temp\production_scanner_final.png"} -ErrorAction SilentlyContinue
} catch {}

# 3. Read the INI file
$iniPath = Get-BcWebCamIniPath
$ini = Read-IniFile -Path $iniPath

# 4. Extract relevant settings
$generalSection = if ($ini.ContainsKey("General")) { $ini["General"] } else { @{} }
$barcodeLSection = if ($ini.ContainsKey("BarcodeL")) { $ini["BarcodeL"] } else { @{} }
$barcodePSection = if ($ini.ContainsKey("BarcodeP")) { $ini["BarcodeP"] } else { @{} }
$barcodeDSection = if ($ini.ContainsKey("BarcodeD")) { $ini["BarcodeD"] } else { @{} }

$result = @{
    task = "configure_production_scanner"
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    ini_exists = (Test-Path $iniPath)
    ini_path = $iniPath
    general = @{
        SendKeysPostfix = if ($generalSection.ContainsKey("SendKeysPostfix")) { $generalSection["SendKeysPostfix"] } else { $null }
        BcGracePeriod   = if ($generalSection.ContainsKey("BcGracePeriod"))   { $generalSection["BcGracePeriod"] }   else { $null }
        Opacity         = if ($generalSection.ContainsKey("Opacity"))         { $generalSection["Opacity"] }         else { $null }
        Beep            = if ($generalSection.ContainsKey("Beep"))            { $generalSection["Beep"] }            else { $null }
        FlipBitmap      = if ($generalSection.ContainsKey("FlipBitmap"))      { $generalSection["FlipBitmap"] }      else { $null }
        TopMost         = if ($generalSection.ContainsKey("TopMost"))         { $generalSection["TopMost"] }         else { $null }
    }
    barcode_l_type = if ($barcodeLSection.ContainsKey("Type")) { $barcodeLSection["Type"] } else { $null }
    barcode_p_type = if ($barcodePSection.ContainsKey("Type")) { $barcodePSection["Type"] } else { $null }
    barcode_d_type = if ($barcodeDSection.ContainsKey("Type")) { $barcodeDSection["Type"] } else { $null }
}

# 5. Save to JSON
$resultPath = "C:\Windows\Temp\configure_production_scanner_result.json"
$result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding UTF8
Write-Host "Result JSON written to: $resultPath"

# 6. Display summary for debugging
Write-Host "FlipBitmap: $($result.general.FlipBitmap)"
Write-Host "BarcodeL Type: $($result.barcode_l_type)"
Write-Host "SendKeysPostfix: $($result.general.SendKeysPostfix)"
Write-Host "BcGracePeriod: $($result.general.BcGracePeriod)"

Write-Host "=== Export Complete ==="
