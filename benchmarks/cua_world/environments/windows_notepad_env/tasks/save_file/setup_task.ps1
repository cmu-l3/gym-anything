# Setup script for save_file task

# Create the sample file
$TasksDir = "C:\Users\Docker\Desktop\Tasks"
New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

@"
This is the original content of sample.txt
Line 2 of the original file
"@ | Out-File -FilePath "$TasksDir\sample.txt" -Encoding UTF8

# Close any open Notepad windows
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Task setup complete - sample.txt created"
