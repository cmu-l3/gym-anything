# setup_task.ps1 — Pre-task setup for checkin_returning_visitor

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up checkin_returning_visitor task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Record task start time
Record-TaskStartTime -TaskName "checkin_returning_visitor"

# Kill any existing Lobby Track instances
Close-LobbyTrack

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

# Create historical visitors CSV for import
$csvContent = @"
First Name,Last Name,Company,Email,Phone,Visitor Group,Host Name,Purpose
David,Miller,Acme Corp,david.m@acme.com,555-0101,Visitor,James Wilson,Meeting
Sarah,Chen,Deloitte,schen@deloitte.com,555-0102,Visitor,David Park,Meeting
Jessica,Wong,Consulting Partners,j.wong@cp.com,555-0103,Visitor,Emily Davis,Vendor
"@
[System.IO.File]::WriteAllText("C:\Users\Docker\Documents\historical_visitors.csv", $csvContent)

# Launch Lobby Track
Ensure-LobbyTrackRunning

# Minimize terminal windows
Minimize-TerminalWindows

Write-Host "=== checkin_returning_visitor setup complete ==="
