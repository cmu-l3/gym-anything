# Setup script for find_replace task

$TasksDir = "C:\Users\Docker\Desktop\Tasks"
New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

# Create document with multiple occurrences of 'old'
@"
This is an old document with old content.
The old version needs to be updated.
Replace old text with new text.
Keep the old formatting but update old words.
"@ | Out-File -FilePath "$TasksDir\document.txt" -Encoding UTF8

Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Task setup complete - document.txt created with 'old' occurrences"
