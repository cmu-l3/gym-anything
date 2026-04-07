[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting hazard_reclassification_audit result ==="

. C:\workspace\scripts\task_utils.ps1

Start-Sleep -Seconds 3
Stop-Tier2Submit

$targetFile = "C:\Users\Docker\Desktop\Tier2Output\corrected_hazards.t2s"
$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_hazard_reclassification_audit.txt" -ErrorAction SilentlyContinue) } catch { }

if (-not (Test-Path $targetFile)) {
    Write-Host "Target file not found: $targetFile"
    Write-ResultJson -TaskName "hazard_reclassification_audit" -Data @{
        file_exists = $false
        start_timestamp = $startTimestamp
        chemicals = @()
    }
    exit 0
}

$fileInfo = Get-Item $targetFile
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

# Parse .t2s (ZIP containing XML)
$extractPath = "C:\Users\Docker\Desktop\t2s_extracted_hazaudit"
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

$chemicals = @()

try {
    $zipPath = "$extractPath\report.zip"
    Copy-Item $targetFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $xmlFile = Get-ChildItem $extractPath -Filter "*.xml" -Recurse | Select-Object -First 1
    if ($xmlFile) {
        [xml]$xmlDoc = Get-Content $xmlFile.FullName -Raw -Encoding UTF8
        $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $ns.AddNamespace("t2", "https://cameo.noaa.gov/epcra_tier2/data_standard/v1")

        $chemNodes = $xmlDoc.SelectNodes("//t2:chemical", $ns)
        foreach ($chem in $chemNodes) {
            $hazardMap = @{}
            $hazardNodes = $chem.SelectNodes("t2:hazards/t2:hazard", $ns)
            foreach ($h in $hazardNodes) {
                $cat = $h.SelectSingleNode("t2:category", $ns)
                $val = $h.SelectSingleNode("t2:value", $ns)
                if ($cat) {
                    $hazardMap[$cat.InnerText] = if ($val) { $val.InnerText } else { "false" }
                }
            }

            $chemicals += @{
                name = ($chem.SelectSingleNode("t2:chemName", $ns)).InnerText
                cas = ($chem.SelectSingleNode("t2:casNumber", $ns)).InnerText
                hazards = $hazardMap
            }
        }
        Write-Host "Parsed $($chemicals.Count) chemicals"
    }
} catch {
    Write-Host "WARNING: Failed to parse .t2s: $($_.Exception.Message)"
}

Write-ResultJson -TaskName "hazard_reclassification_audit" -Data @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    chemical_count = $chemicals.Count
    chemicals = $chemicals
}

try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export complete ==="
