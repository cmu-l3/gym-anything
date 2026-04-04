# Setup script for Windows Notepad environment
# This script runs after Windows boots (post_start hook)

Write-Host "Setting up Notepad environment..."

# Create a working directory on the Desktop
$TasksDir = "C:\Users\Docker\Desktop\Tasks"
New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

# Create a sample text file for tasks
@"
This is a sample text file for testing.
You can edit this file using Notepad.
"@ | Out-File -FilePath "$TasksDir\sample.txt" -Encoding UTF8

Write-Host "Setup complete!"
Write-Host "Tasks directory: $TasksDir"
