[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting facility_audit_correction result ==="

. C:\workspace\scripts\task_utils.ps1

Start-Sleep -Seconds 3
Stop-Tier2Submit

$targetFile = "C:\Users\Docker\Desktop\Tier2Output\facility_corrected.t2s"
$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_facility_audit_correction.txt" -ErrorAction SilentlyContinue) } catch { }

if (-not (Test-Path $targetFile)) {
    Write-Host "Target file not found: $targetFile"
    Write-ResultJson -TaskName "facility_audit_correction" -Data @{
        file_exists = $false
        start_timestamp = $startTimestamp
    }
    exit 0
}

$fileInfo = Get-Item $targetFile
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

$extractPath = "C:\Users\Docker\Desktop\t2s_extracted_facaudit"
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

$facilityData = @{}

try {
    $zipPath = "$extractPath\report.zip"
    Copy-Item $targetFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $xmlFile = Get-ChildItem $extractPath -Filter "*.xml" -Recurse | Select-Object -First 1
    if ($xmlFile) {
        [xml]$xmlDoc = Get-Content $xmlFile.FullName -Raw -Encoding UTF8
        $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $ns.AddNamespace("t2", "https://cameo.noaa.gov/epcra_tier2/data_standard/v1")

        $fac = $xmlDoc.SelectSingleNode("//t2:facility", $ns)
        if ($fac) {
            $countyNode = $fac.SelectSingleNode("t2:county", $ns)
            $latNode = $fac.SelectSingleNode("t2:latLong/t2:latitude", $ns)
            $lonNode = $fac.SelectSingleNode("t2:latLong/t2:longitude", $ns)
            $mailCityNode = $fac.SelectSingleNode("t2:mailingAddress/t2:city", $ns)

            $facilityData["county"] = if ($countyNode) { $countyNode.InnerText } else { "" }
            $facilityData["latitude"] = if ($latNode) { $latNode.InnerText } else { "" }
            $facilityData["longitude"] = if ($lonNode) { $lonNode.InnerText } else { "" }
            $facilityData["mailing_city"] = if ($mailCityNode) { $mailCityNode.InnerText } else { "" }
        }

        # Extract NAICS code
        $naicsNode = $xmlDoc.SelectSingleNode("//t2:facilityId[@type='NAICS']/t2:id", $ns)
        $naicsDescNode = $xmlDoc.SelectSingleNode("//t2:facilityId[@type='NAICS']/t2:description", $ns)
        $facilityData["naics_code"] = if ($naicsNode) { $naicsNode.InnerText } else { "" }
        $facilityData["naics_description"] = if ($naicsDescNode) { $naicsDescNode.InnerText } else { "" }

        Write-Host "Facility data extracted."
    }
} catch {
    Write-Host "WARNING: Failed to parse .t2s: $($_.Exception.Message)"
}

Write-ResultJson -TaskName "facility_audit_correction" -Data @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    facility = $facilityData
}

try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export complete ==="
