# setup_task.ps1 — Pre-task setup for contractor_overstay_watchlist_enforcement
#
# This task requires the agent to:
#   1. Analyze December 2025 contractor visit durations from CSV data
#   2. Identify contractors who exceeded the 120-minute on-site policy
#   3. Add each violator to Lobby Track's Denied Visitor Watchlist with tiered enforcement
#   4. Create a compliance report CSV on the Desktop
#
# Setup seeds the base visitor data plus two additional contractor overstay records,
# clears previous artifacts, and ensures Lobby Track is running.

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up contractor_overstay_watchlist_enforcement task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Kill any existing Lobby Track instances for clean state
Close-LobbyTrack

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

# Copy base data files (visitor_records.csv, employee_hosts.csv)
if (Test-Path "C:\workspace\data") {
    Copy-Item "C:\workspace\data\*" -Destination "C:\Users\Docker\LobbyTrack\data\" -Recurse -Force -ErrorAction SilentlyContinue
}

# Append two additional contractor records that create additional overstay violations.
# These are realistic records that extend the existing December 2025 dataset:
#   - Alex Rivera / Siemens AG: 09:00-11:15 = 135 min (15 min over) -> WARNING tier
#   - Rachel Kim / McKinsey & Co: 08:30-12:00 = 210 min (90 min over) -> BANNED tier
$csvPath = "C:\Users\Docker\LobbyTrack\data\visitor_records.csv"
if (Test-Path $csvPath) {
    $extraRecords = @(
        "Alex,Rivera,Siemens AG,alex.rivera@siemens.com,555-0199,Safety Inspection,Jennifer,Adams,Facilities,2025-12-20,09:00,11:15,Contractor"
        "Rachel,Kim,McKinsey & Co,rachel.kim@mckinsey.com,555-0200,Process Review,Patricia,Lopez,Operations,2025-12-22,08:30,12:00,Contractor"
    )
    foreach ($record in $extraRecords) {
        Add-Content -Path $csvPath -Value $record -Encoding UTF8
    }
    Write-Host "Appended 2 additional contractor records to visitor_records.csv"
} else {
    Write-Host "WARNING: visitor_records.csv not found at $csvPath"
}

# Also copy CSVs to Documents for discoverability
Copy-Item "C:\Users\Docker\LobbyTrack\data\*.csv" -Destination "C:\Users\Docker\Documents\" -Force -ErrorAction SilentlyContinue

# Remove stale output artifacts BEFORE recording timestamp (anti-gaming)
Remove-Item "C:\Users\Docker\Desktop\watchlist_enforcement_dec2025.csv" -Force -ErrorAction SilentlyContinue

# Record task start time (after cleanup so timestamp is clean reference point)
Record-TaskStartTime -TaskName "contractor_overstay_watchlist_enforcement"

# Launch Lobby Track and dismiss startup dialogs
Ensure-LobbyTrackRunning

# Minimize terminal windows so the agent sees a clean desktop
Minimize-TerminalWindows

Write-Host "=== contractor_overstay_watchlist_enforcement setup complete ==="
