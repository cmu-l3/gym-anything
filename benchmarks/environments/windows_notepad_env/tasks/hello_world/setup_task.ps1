# Setup script for hello_world task
# Ensures clean state before task begins

# Remove any existing hello.txt from Desktop
$HelloPath = "C:\Users\Docker\Desktop\hello.txt"
if (Test-Path $HelloPath) {
    Remove-Item $HelloPath -Force
}

# Close any open Notepad windows
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Task cleanup complete - ready for hello_world task"

# Note: Notepad will be opened by the init_script via PyAutoGUI after this hook completes
