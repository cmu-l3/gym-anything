# setup_task.ps1 — Pre-task setup for purge_historical_records

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up purge_historical_records task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Record task start time
Record-TaskStartTime -TaskName "purge_historical_records"

# Kill any existing Lobby Track instances
Close-LobbyTrack

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

# Generate legacy visitor CSV with mix of old and new records
# Records before Jan 1, 2023 should be purged; newer ones kept
$legacyCsv = @"
First Name,Last Name,Company,Visit Date
Arthur,Dent,Galactic Imports,05/15/2020
Ford,Prefect,Guide Publications,02/01/2024
Zaphod,Beeblebrox,Government,01/01/2019
Tricia,McMillan,Science Inst,06/15/2023
Marvin,Android,Sirius Cybernetics,12/31/2022
Slartibartfast,Builder,Magrathea,03/10/2025
Visitor0,Test0,TestCorp,07/22/2020
Visitor1,Test1,TestCorp,11/03/2021
Visitor2,Test2,TestCorp,04/17/2019
Visitor3,Test3,TestCorp,08/29/2023
Visitor4,Test4,TestCorp,01/12/2024
Visitor5,Test5,TestCorp,09/05/2022
Visitor6,Test6,TestCorp,03/18/2020
Visitor7,Test7,TestCorp,06/30/2024
Visitor8,Test8,TestCorp,10/14/2021
Visitor9,Test9,TestCorp,02/25/2023
"@
[System.IO.File]::WriteAllText("C:\Users\Docker\Desktop\legacy_visitor_log.csv", $legacyCsv)
Write-Host "Legacy CSV created at C:\Users\Docker\Desktop\legacy_visitor_log.csv"

# Remove any previous audit proof
Remove-Item "C:\Users\Docker\Documents\audit_proof.csv" -Force -ErrorAction SilentlyContinue

# Launch Lobby Track
Ensure-LobbyTrackRunning

# Minimize terminal windows
Minimize-TerminalWindows

Write-Host "=== purge_historical_records setup complete ==="
