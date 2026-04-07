# setup_task.ps1 — Pre-task setup for restore_visitor_database

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up restore_visitor_database task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Record task start time
Record-TaskStartTime -TaskName "restore_visitor_database"

# Kill any existing Lobby Track instances
Close-LobbyTrack

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\LobbyTrackBackup" | Out-Null

# Create backup database by copying installed database
Write-Host "Preparing backup database..."
$sourceDb = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "*.mdb" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "Lobby|Track|Sample" } | Select-Object -First 1
if ($sourceDb) {
    Copy-Item $sourceDb.FullName -Destination "C:\LobbyTrackBackup\LobbyTrackDB_backup.mdb" -Force
    Write-Host "Backup database created from: $($sourceDb.FullName)"
} else {
    # Create a placeholder file
    New-Item -Path "C:\LobbyTrackBackup\LobbyTrackDB_backup.mdb" -ItemType File -Force | Out-Null
    Write-Host "WARNING: No source database found, created placeholder backup"
}

# Remove any existing confirmation file
Remove-Item "C:\LobbyTrackBackup\restore_confirmation.txt" -Force -ErrorAction SilentlyContinue

# Launch Lobby Track
Ensure-LobbyTrackRunning

# Minimize terminal windows
Minimize-TerminalWindows

Write-Host "=== restore_visitor_database setup complete ==="
