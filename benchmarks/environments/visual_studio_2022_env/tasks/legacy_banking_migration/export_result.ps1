# Export script for legacy_banking_migration task.
# Reads source files and build results, writes verification JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_export_legacy_banking_migration.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting legacy_banking_migration result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils }

    $resultPath  = "C:\Users\Docker\legacy_banking_migration_result.json"
    $startTsFile = "C:\Users\Docker\task_start_ts_legacy_banking_migration.txt"

    $taskStart = 0
    if (Test-Path $startTsFile) {
        $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
    }

    # Kill VS so any auto-saves are flushed and file locks released
    if (Get-Command Kill-AllVS2022 -ErrorAction SilentlyContinue) {
        Kill-AllVS2022
    } else {
        Get-Process devenv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    $projDir = "C:\Users\Docker\source\repos\BankingCore"

    # --- Read TransactionProcessor.cs ---
    $processorPath = "$projDir\TransactionProcessor.cs"
    $processorContent = ""
    $processorIsNew = $false
    if (Test-Path $processorPath) {
        $processorContent = Get-Content $processorPath -Raw -ErrorAction SilentlyContinue
        $fi = Get-Item $processorPath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $processorIsNew = ($mtime -gt $taskStart)
    }

    # --- Pattern detection in TransactionProcessor.cs ---
    # Anti-patterns that should be REMOVED:
    $hasArrayList   = $processorContent -match "new ArrayList\b"
    $hasHashtable   = $processorContent -match "new Hashtable\b"
    $hasDateTimeNow = ($processorContent -match "DateTime\.Now\b") -or
                      ($processorContent -match "DateTime\.Now[^O]") # exclude DateTime.Now.ToString etc.
    # Detect new Random() for ID generation — look for both new Random and use of _rng.Next
    $hasSystemRandom = ($processorContent -match "new Random\(\)") -or
                       ($processorContent -match "\bnew Random\b")
    # Detect string concatenation in a loop (approximate: += inside foreach)
    $hasStringConcatLoop = $processorContent -match "(?s)foreach[^{]*\{[^}]*report\s*\+="

    # Patterns that should be ADDED:
    $hasGenericList   = $processorContent -match "List<Transaction>"
    $hasGenericDict   = $processorContent -match "Dictionary<string"
    $hasDateTimeOffset = $processorContent -match "DateTimeOffset"
    $hasSecureRng     = ($processorContent -match "RandomNumberGenerator") -or
                        ($processorContent -match "RNGCryptoServiceProvider") -or
                        ($processorContent -match "GetInt32\b") -or
                        ($processorContent -match "GetBytes\b")
    $hasStringBuilder = $processorContent -match "StringBuilder"

    # --- Run dotnet build ---
    $dotnetExe = "C:\Program Files\dotnet\dotnet.exe"
    if (-not (Test-Path $dotnetExe)) {
        $dc = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dc) { $dotnetExe = $dc.Source }
    }

    $buildSuccess = $false
    $buildErrors  = 999
    $buildOutput  = ""
    if ((Test-Path $dotnetExe) -and (Test-Path "$projDir\BankingCore.csproj")) {
        $buildOutput = & $dotnetExe build $projDir --nologo 2>&1 | Out-String
        $buildSuccess = ($LASTEXITCODE -eq 0)
        $m = [regex]::Match($buildOutput, "(\d+) Error\(s\)")
        if ($m.Success) { $buildErrors = [int]$m.Groups[1].Value }
        elseif ($buildSuccess) { $buildErrors = 0 }
    }

    # Convert booleans to JSON-safe lowercase strings
    function jb([bool]$v) { if ($v) { "true" } else { "false" } }

    $json = @"
{
  "task_start": $taskStart,
  "processor_file_exists": $(jb (Test-Path $processorPath)),
  "processor_modified_after_start": $(jb $processorIsNew),
  "has_array_list": $(jb $hasArrayList),
  "has_hashtable": $(jb $hasHashtable),
  "has_datetime_now": $(jb $hasDateTimeNow),
  "has_system_random": $(jb $hasSystemRandom),
  "has_string_concat_loop": $(jb $hasStringConcatLoop),
  "has_generic_list": $(jb $hasGenericList),
  "has_generic_dict": $(jb $hasGenericDict),
  "has_datetime_offset": $(jb $hasDateTimeOffset),
  "has_secure_rng": $(jb $hasSecureRng),
  "has_stringbuilder": $(jb $hasStringBuilder),
  "build_success": $(jb $buildSuccess),
  "build_errors": $buildErrors
}
"@

    [System.IO.File]::WriteAllText($resultPath, $json, [System.Text.Encoding]::UTF8)
    Write-Host "Result JSON written to: $resultPath"
    Write-Host $json

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
