# setup_task.ps1 — Pre-task setup for import_employees_csv

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up import_employees_csv task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Record task start time
Record-TaskStartTime -TaskName "import_employees_csv"

# Kill any existing Lobby Track instances
Close-LobbyTrack

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

# Create interns CSV file for import
$csvContent = @"
Full Name,Dept,Email Address
Alice Intern,Engineering,alice.intern@example.com
Bob Intern,Engineering,bob.intern@example.com
Charlie Intern,Sales,charlie.intern@example.com
Dana Intern,Marketing,dana.intern@example.com
Evan Intern,Support,evan.intern@example.com
"@
[System.IO.File]::WriteAllText("C:\Users\Docker\Documents\interns.csv", $csvContent)

# Launch Lobby Track
Ensure-LobbyTrackRunning

# Minimize terminal windows
Minimize-TerminalWindows

Write-Host "=== import_employees_csv setup complete ==="
