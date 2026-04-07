[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting inventory_reconciliation_report result ==="

. C:\workspace\scripts\task_utils.ps1

Start-Sleep -Seconds 3
Stop-Tier2Submit

$targetFile = "C:\Users\Docker\Desktop\Tier2Output\reconciled_submission.t2s"
$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_inventory_reconciliation_report.txt" -ErrorAction SilentlyContinue) } catch { }

if (-not (Test-Path $targetFile)) {
    Write-Host "Target file not found: $targetFile"
    Write-ResultJson -TaskName "inventory_reconciliation_report" -Data @{
        file_exists = $false
        start_timestamp = $startTimestamp
    }
    exit 0
}

$fileInfo = Get-Item $targetFile
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

$extractPath = "C:\Users\Docker\Desktop\t2s_extracted_invrecon"
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

$chemicals = @()
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

        # Facility data
        $fac = $xmlDoc.SelectSingleNode("//t2:facility", $ns)
        if ($fac) {
            $occNode = $fac.SelectSingleNode("t2:maxNumOccupants", $ns)
            $certNode = $fac.SelectSingleNode("t2:nameAndTitleOfCertifier", $ns)
            $dateNode = $fac.SelectSingleNode("t2:dateSigned", $ns)
            $facilityData["maxNumOccupants"] = if ($occNode) { $occNode.InnerText } else { "" }
            $facilityData["nameAndTitleOfCertifier"] = if ($certNode) { $certNode.InnerText } else { "" }
            $facilityData["dateSigned"] = if ($dateNode) { $dateNode.InnerText } else { "" }
        }

        # Chemical data
        $chemNodes = $xmlDoc.SelectNodes("//t2:chemical", $ns)
        foreach ($chem in $chemNodes) {
            $storageLocations = @()
            $storageNodes = $chem.SelectNodes("t2:storageLocations/t2:storageLocation", $ns)
            foreach ($sl in $storageNodes) {
                $descNode = $sl.SelectSingleNode("t2:locationDescription", $ns)
                $typeNode = $sl.SelectSingleNode("t2:storageType", $ns)
                $amtNode = $sl.SelectSingleNode("t2:amount", $ns)
                $storageLocations += @{
                    description = if ($descNode) { $descNode.InnerText } else { "" }
                    storageType = if ($typeNode) { $typeNode.InnerText } else { "" }
                    amount = if ($amtNode) { $amtNode.InnerText } else { "" }
                }
            }

            $chemNameNode = $chem.SelectSingleNode("t2:chemName", $ns)
            $casNode = $chem.SelectSingleNode("t2:casNumber", $ns)
            $maxAmtNode = $chem.SelectSingleNode("t2:maxAmount", $ns)
            $maxCodeNode = $chem.SelectSingleNode("t2:maxAmountCode", $ns)
            $aveAmtNode = $chem.SelectSingleNode("t2:aveAmount", $ns)
            $aveCodeNode = $chem.SelectSingleNode("t2:aveAmountCode", $ns)

            $chemicals += @{
                name = if ($chemNameNode) { $chemNameNode.InnerText } else { "" }
                cas = if ($casNode) { $casNode.InnerText } else { "" }
                maxAmount = if ($maxAmtNode) { $maxAmtNode.InnerText } else { "0" }
                maxAmountCode = if ($maxCodeNode) { $maxCodeNode.InnerText } else { "" }
                aveAmount = if ($aveAmtNode) { $aveAmtNode.InnerText } else { "0" }
                aveAmountCode = if ($aveCodeNode) { $aveCodeNode.InnerText } else { "" }
                storage_count = $storageLocations.Count
                storage_locations = $storageLocations
            }
        }
        Write-Host "Parsed $($chemicals.Count) chemicals"
    }
} catch {
    Write-Host "WARNING: Failed to parse .t2s: $($_.Exception.Message)"
}

Write-ResultJson -TaskName "inventory_reconciliation_report" -Data @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    facility = $facilityData
    chemical_count = $chemicals.Count
    chemicals = $chemicals
}

try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export complete ==="
