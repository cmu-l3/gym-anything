[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting regulatory_notification_chemical_entry result ==="

. C:\workspace\scripts\task_utils.ps1

Start-Sleep -Seconds 3
Stop-Tier2Submit

$targetFile = "C:\Users\Docker\Desktop\Tier2Output\new_chemicals_added.t2s"
$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_regulatory_notification_chemical_entry.txt" -ErrorAction SilentlyContinue) } catch { }

if (-not (Test-Path $targetFile)) {
    Write-Host "Target file not found: $targetFile"
    Write-ResultJson -TaskName "regulatory_notification_chemical_entry" -Data @{
        file_exists = $false
        start_timestamp = $startTimestamp
        chemicals = @()
    }
    exit 0
}

$fileInfo = Get-Item $targetFile
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

$extractPath = "C:\Users\Docker\Desktop\t2s_extracted_regnotif"
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
            $hazardList = @()
            $hazardNodes = $chem.SelectNodes("t2:hazards/t2:hazard", $ns)
            foreach ($h in $hazardNodes) {
                $cat = $h.SelectSingleNode("t2:category", $ns)
                $val = $h.SelectSingleNode("t2:value", $ns)
                if ($cat -and $val -and $val.InnerText -eq "true") {
                    $hazardList += $cat.InnerText
                }
            }

            $storageLocations = @()
            $storageNodes = $chem.SelectNodes("t2:storageLocations/t2:storageLocation", $ns)
            foreach ($sl in $storageNodes) {
                $storageLocations += @{
                    description = ($sl.SelectSingleNode("t2:locationDescription", $ns)).InnerText
                    storageType = ($sl.SelectSingleNode("t2:storageType", $ns)).InnerText
                    pressure = ($sl.SelectSingleNode("t2:pressure", $ns)).InnerText
                    temperature = ($sl.SelectSingleNode("t2:temperature", $ns)).InnerText
                    amount = ($sl.SelectSingleNode("t2:amount", $ns)).InnerText
                }
            }

            $chemNameNode = $chem.SelectSingleNode("t2:chemName", $ns)
            $casNode = $chem.SelectSingleNode("t2:casNumber", $ns)
            $ehsNode = $chem.SelectSingleNode("t2:ehs", $ns)
            $pureNode = $chem.SelectSingleNode("t2:pure", $ns)
            $maxAmtNode = $chem.SelectSingleNode("t2:maxAmount", $ns)
            $maxCodeNode = $chem.SelectSingleNode("t2:maxAmountCode", $ns)
            $aveAmtNode = $chem.SelectSingleNode("t2:aveAmount", $ns)
            $aveCodeNode = $chem.SelectSingleNode("t2:aveAmountCode", $ns)
            $daysNode = $chem.SelectSingleNode("t2:daysOnSite", $ns)

            $chemicals += @{
                name = if ($chemNameNode) { $chemNameNode.InnerText } else { "" }
                cas = if ($casNode) { $casNode.InnerText } else { "" }
                ehs = if ($ehsNode) { $ehsNode.InnerText } else { "false" }
                pure = if ($pureNode) { $pureNode.InnerText } else { "false" }
                maxAmount = if ($maxAmtNode) { $maxAmtNode.InnerText } else { "0" }
                maxAmountCode = if ($maxCodeNode) { $maxCodeNode.InnerText } else { "" }
                aveAmount = if ($aveAmtNode) { $aveAmtNode.InnerText } else { "0" }
                aveAmountCode = if ($aveCodeNode) { $aveCodeNode.InnerText } else { "" }
                daysOnSite = if ($daysNode) { $daysNode.InnerText } else { "0" }
                hazards_true = $hazardList
                storage_locations = $storageLocations
            }
        }
        Write-Host "Parsed $($chemicals.Count) chemicals"
    }
} catch {
    Write-Host "WARNING: Failed to parse .t2s: $($_.Exception.Message)"
}

Write-ResultJson -TaskName "regulatory_notification_chemical_entry" -Data @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    chemical_count = $chemicals.Count
    chemicals = $chemicals
}

try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export complete ==="
