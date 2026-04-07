#!/bin/bash
echo "=== Exporting saltbox_roof_solar task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use PowerShell to safely gather file statistics inside Windows
powershell.exe -Command "
\$result = @{
    output_exists = \$false
    file_created_during_task = \$false
    output_size_bytes = 0
    output_mtime = 0
}

\$task_start = $TASK_START
\$outputPath = 'C:\Users\Docker\Documents\saltbox_solar.skp'

if (Test-Path \$outputPath) {
    \$file = Get-Item \$outputPath
    \$result.output_exists = \$true
    \$result.output_size_bytes = \$file.Length
    
    # Get Unix timestamp for LastWriteTime
    \$mtime = [int][double]::Parse((Get-Date \$file.LastWriteTime -UFormat %s))
    \$result.output_mtime = \$mtime
    
    if (\$mtime -gt \$task_start) {
        \$result.file_created_during_task = \$true
    }
}

# Ensure directory exists and write result
if (-not (Test-Path 'C:\tmp')) { New-Item -ItemType Directory -Force -Path 'C:\tmp' | Out-Null }
\$json = \$result | ConvertTo-Json -Compress
[IO.File]::WriteAllText('C:\tmp\task_result.json', \$json)
"

# Copy the file to the Linux-accessible /tmp path for the verifier
mkdir -p /tmp
cp /c/tmp/task_result.json /tmp/task_result.json 2>/dev/null || true

# Fallback: if CP failed, read it out directly via powershell
if [ ! -f "/tmp/task_result.json" ]; then
    powershell.exe -Command "Get-Content 'C:\tmp\task_result.json'" > /tmp/task_result.json
fi

echo "Exported Result:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="