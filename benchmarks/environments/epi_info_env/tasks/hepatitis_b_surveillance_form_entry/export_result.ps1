# Export: hepatitis_b_surveillance_form_entry
# Checks project file existence, queries record count via Jet OLEDB, checks HTML

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting hepatitis_b_surveillance_form_entry Result ==="

$resultPath  = "C:\Users\Docker\hepatitis_b_surveillance_form_entry_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_hepb.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

function Get-FileResult {
    param([string]$FilePath, [bool]$ReadContent = $false, [int]$MaxLen = 2000)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $content = ""
        if ($ReadContent) {
            try {
                $raw = [System.IO.File]::ReadAllText($FilePath)
                $content = if ($raw.Length -gt $MaxLen) { $raw.Substring(0, $MaxLen) } else { $raw }
            } catch {}
        }
        return @{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)
            content    = $content
        }
    }
    return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false; content = "" }
}

# Check project file
$prjResult = Get-FileResult "C:\Users\Docker\Documents\HepBSurveillance.prj"

# Check MDB file
$mdbPath = "C:\Users\Docker\Documents\HepBSurveillance.mdb"
$mdbResult = Get-FileResult $mdbPath

# Query record count from MDB using 32-bit PowerShell + Jet OLEDB
$recordCount    = 0
$tableExists    = $false
$mdbQueryScript = @"
`$mdbPath = "$mdbPath"
if (-not (Test-Path `$mdbPath)) {
    Write-Output "MDB_NOT_FOUND"
} else {
    try {
        `$conn = New-Object -ComObject ADODB.Connection
        `$conn.Open("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=`$mdbPath")
        try {
            `$rs = `$conn.Execute("SELECT COUNT(*) FROM CaseReport")
            `$count = `$rs.Fields[0].Value
            `$rs.Close()
            `$conn.Close()
            Write-Output "COUNT:`$count"
        } catch {
            # Try alternate table naming (Epi Info sometimes lowercases)
            try {
                `$rs = `$conn.Execute("SELECT COUNT(*) FROM casereport")
                `$count = `$rs.Fields[0].Value
                `$rs.Close()
                `$conn.Close()
                Write-Output "COUNT:`$count"
            } catch {
                `$conn.Close()
                Write-Output "TABLE_NOT_FOUND"
            }
        }
    } catch {
        Write-Output "CONN_FAILED:`$_"
    }
}
"@

$tmpQScript = "C:\Windows\Temp\query_hepb_mdb.ps1"
$mdbQueryScript | Out-File -FilePath $tmpQScript -Encoding ASCII -Force
$queryOutput = & "C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File $tmpQScript 2>&1
$queryOutput = $queryOutput -join ""

Write-Host "MDB query output: $queryOutput"

if ($queryOutput -match "COUNT:(\d+)") {
    $recordCount = [int]$Matches[1]
    $tableExists = $true
} elseif ($queryOutput -contains "TABLE_NOT_FOUND") {
    $tableExists = $false
    $recordCount = 0
}

# Check HTML output
$htmlPath = "C:\Users\Docker\hepb_analysis.html"
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\hepb_analysis.htm" }
$htmlResult = Get-FileResult $htmlPath -ReadContent $true -MaxLen 50000

$htmlLower = $htmlResult.content.ToLower()
$hasFreqKw   = $htmlLower.Contains("frequency") -or $htmlLower.Contains("freq")
$hasHepBKw   = $htmlLower.Contains("hbsag") -or $htmlLower.Contains("hepatitis") -or $htmlLower.Contains("vaccination") -or $htmlLower.Contains("casereport") -or $htmlLower.Contains("hepb")
$hasFieldKw  = $htmlLower.Contains("sex") -or $htmlLower.Contains("county") -or $htmlLower.Contains("source") -or $htmlLower.Contains("clinical") -or $htmlLower.Contains("age")
$hasMeansKw  = $htmlLower.Contains("mean") -or $htmlLower.Contains("standard deviation") -or $htmlLower.Contains("ageatdiagnosis")

$result = [ordered]@{
    task          = "hepatitis_b_surveillance_form_entry"
    task_start    = $taskStart
    prj_file      = @{
        exists     = $prjResult.exists
        size_bytes = $prjResult.size_bytes
        mtime_unix = $prjResult.mtime_unix
        is_new     = $prjResult.is_new
    }
    mdb_file      = @{
        exists       = $mdbResult.exists
        size_bytes   = $mdbResult.size_bytes
        mtime_unix   = $mdbResult.mtime_unix
        is_new       = $mdbResult.is_new
        table_exists = $tableExists
        record_count = $recordCount
    }
    html_output   = @{
        exists        = $htmlResult.exists
        size_bytes    = $htmlResult.size_bytes
        mtime_unix    = $htmlResult.mtime_unix
        is_new        = $htmlResult.is_new
        has_freq_kw   = $hasFreqKw
        has_hepb_kw   = $hasHepBKw
        has_field_kw  = $hasFieldKw
        has_means_kw  = $hasMeansKw
    }
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "Record count in HepBSurveillance.mdb:CaseReport = $recordCount"
Write-Host "=== Export Complete ==="
