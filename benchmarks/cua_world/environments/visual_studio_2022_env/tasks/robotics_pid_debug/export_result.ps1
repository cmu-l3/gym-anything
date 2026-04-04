<#
  export_result.ps1 - ArmController robotics PID debug result export
  Reads source files, detects bug presence/absence, builds, writes JSON.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir  = "C:\Users\Docker\source\repos\ArmController"
$ResultPath  = "C:\Users\Docker\robotics_pid_debug_result.json"
$TsFile      = "C:\Users\Docker\robotics_pid_debug_start_ts.txt"

Write-Host "=== Exporting robotics_pid_debug result ==="

# ── 1. Kill VS ────────────────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 3

# ── 2. Read task start timestamp ──────────────────────────────────────────────
$taskStart = 0
if (Test-Path $TsFile) {
    $taskStart = [int](Get-Content $TsFile -Raw).Trim()
}

# ── 3. Read source files ──────────────────────────────────────────────────────
function Read-Src($path) {
    if (Test-Path $path) { return (Get-Content $path -Raw -Encoding UTF8) }
    return ""
}

$pidSrc    = Read-Src "$ProjectDir\PidController.cs"
$limSrc    = Read-Src "$ProjectDir\JointLimiter.cs"
$scalerSrc = Read-Src "$ProjectDir\VelocityScaler.cs"

# ── 4. Check modification times ───────────────────────────────────────────────
function Was-Modified($path, $since) {
    if (-not (Test-Path $path)) { return $false }
    $mt = [int][DateTimeOffset]::new((Get-Item $path).LastWriteTimeUtc).ToUnixTimeSeconds()
    return $mt -gt $since
}

$pidModified    = Was-Modified "$ProjectDir\PidController.cs"   $taskStart
$limModified    = Was-Modified "$ProjectDir\JointLimiter.cs"    $taskStart
$scalerModified = Was-Modified "$ProjectDir\VelocityScaler.cs"  $taskStart
$anyModified    = $pidModified -or $limModified -or $scalerModified

# ── 5. BUG 1: PID derivative term sign ────────────────────────────────────────
# Original bug: (_previousError - error) / dt  → inverted derivative
# Correct:      (error - _previousError) / dt
$pidHasBug  = $pidSrc -match "_previousError\s*-\s*error\b" -and
              -not ($pidSrc -match "\berror\s*-\s*_previousError\b")
$pidFixed   = $pidSrc -match "\berror\s*-\s*_previousError\b" -and
              -not ($pidSrc -match "_previousError\s*-\s*error\b")

# ── 6. BUG 2: JointLimiter inverted condition ──────────────────────────────────
# Original bug:  if (angle > Min && angle < Max) { return Math.Clamp(...) } else { return angle; }
# This returns raw (unclamped) angle for out-of-range values.
# Fixed: if (angle < Min || angle > Max) clamp; else return as-is.
# Or simply: return Math.Clamp(angle, MinAngle, MaxAngle); — no condition needed.
$limHasBug = $limSrc -match "return requestedAngle;" -and
             ($limSrc -match "requestedAngle\s*>\s*MinAngle\s*&&\s*requestedAngle\s*<\s*MaxAngle" -or
              $limSrc -match ">\s*MinAngle\s*&&.*<\s*MaxAngle")
$limFixed  = -not ($limSrc -match "return requestedAngle\s*;") -or
             ($limSrc -match "Math\.Clamp\s*\(requestedAngle,\s*MinAngle,\s*MaxAngle\s*\)" -and
              -not ($limSrc -match "requestedAngle\s*>\s*MinAngle\s*&&\s*requestedAngle\s*<\s*MaxAngle.*else.*return requestedAngle"))

# ── 7. BUG 3: VelocityScaler multiply vs divide ───────────────────────────────
# Original bug: return velocityMilliRadPerSec * MilliRadiansPerRadian  (mrad/s * 1000 = wrong!)
# Correct:      return velocityMilliRadPerSec / MilliRadiansPerRadian  (mrad/s / 1000 = rad/s)
$scalerHasBug = $scalerSrc -match "velocityMilliRadPerSec\s*\*\s*MilliRadiansPerRadian" -and
                -not ($scalerSrc -match "velocityMilliRadPerSec\s*/\s*MilliRadiansPerRadian")
$scalerFixed  = $scalerSrc -match "velocityMilliRadPerSec\s*/\s*(MilliRadiansPerRadian|1000)" -and
                -not ($scalerSrc -match "velocityMilliRadPerSec\s*\*\s*MilliRadiansPerRadian")

# ── 8. Build ──────────────────────────────────────────────────────────────────
$dotnet = Find-DotnetExe
$buildOut    = & $dotnet build "$ProjectDir\ArmController.csproj" --configuration Release 2>&1
$buildStr    = $buildOut -join "`n"
$buildSuccess = $buildStr -match "Build succeeded"
$errMatch    = [regex]::Match($buildStr, "(\d+)\s+Error\(s\)")
$buildErrors = if ($errMatch.Success) { [int]$errMatch.Groups[1].Value } else { 0 }
if (-not $buildSuccess) { $buildErrors = [Math]::Max($buildErrors, 1) }

Write-Host "Build: $buildSuccess, Errors: $buildErrors"
Write-Host "PID fixed: $pidFixed | Limiter fixed: $limFixed | Scaler fixed: $scalerFixed"

# ── 9. Write result JSON ──────────────────────────────────────────────────────
$result = [ordered]@{
    task_start      = $taskStart
    any_modified    = $anyModified
    pid_modified    = $pidModified
    lim_modified    = $limModified
    scaler_modified = $scalerModified
    pid_has_bug     = [bool]$pidHasBug
    pid_fixed       = [bool]$pidFixed
    lim_has_bug     = [bool]$limHasBug
    lim_fixed       = [bool]$limFixed
    scaler_has_bug  = [bool]$scalerHasBug
    scaler_fixed    = [bool]$scalerFixed
    build_success   = [bool]$buildSuccess
    build_errors    = $buildErrors
}

$result | ConvertTo-Json -Depth 5 | Set-Content $ResultPath -Encoding UTF8

Write-Host "Result written to $ResultPath"
Write-Host "=== Export complete ==="
