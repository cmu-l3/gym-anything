Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_customize_accessibility_profile.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up customize_accessibility_profile task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Record task start timestamp
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_customize_accessibility_profile.txt", $timestamp)

    # Ensure the letter.talon-list exists at the correct path with original non-NATO content
    $letterDir  = "$Script:CommunityDir\core\keys"
    $letterFile = "$letterDir\letter.talon-list"
    New-Item -ItemType Directory -Force -Path $letterDir | Out-Null

    # Restore from data source or write original non-NATO phonetics
    $dataSrc = "C:\workspace\data\community_sample\core\keys\letter.talon-list"
    if (Test-Path $dataSrc) {
        Copy-Item $dataSrc -Destination $letterFile -Force
        Write-Host "Restored letter.talon-list from data source"
    } else {
        # Write the original non-NATO phonetic alphabet used in the community config
        $originalAlphabet = @'
list: user.letter
-
air: a
bat: b
cap: c
drum: d
each: e
fine: f
gust: g
harp: h
sit: i
jury: j
crunch: k
look: l
made: m
near: n
odd: o
pit: p
quench: q
red: r
sun: s
trap: t
urge: u
vest: v
whale: w
plex: x
yank: y
zip: z
'@
        [System.IO.File]::WriteAllText($letterFile, $originalAlphabet)
        Write-Host "Created original non-NATO letter.talon-list"
    }

    # Ensure vocabulary directory exists but medical_terms list does NOT exist yet
    $vocabDir   = "$Script:CommunityDir\core\vocabulary"
    $medFile    = "$vocabDir\user.medical_terms.talon-list"
    New-Item -ItemType Directory -Force -Path $vocabDir | Out-Null
    if (Test-Path $medFile) { Remove-Item $medFile -Force }
    Write-Host "Vocabulary directory ready (medical_terms list removed if existed)"

    # Open the letter file in editor so agent can see the current state
    Open-FileInteractive -FilePath $letterFile -WaitSeconds 7

    Minimize-TerminalWindows

    Write-Host "=== customize_accessibility_profile task setup complete ==="
    Write-Host "=== Letter file: $letterFile ==="
    Write-Host "=== Medical terms file to create: $medFile ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
