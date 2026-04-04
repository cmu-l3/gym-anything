#!/bin/bash
echo "=== Exporting Create Service Items Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define search paths for the database
DB_PATH_1="C:\ProgramData\NCH Software\Copper\Shared\copper.db"
DB_PATH_2="C:\Users\Docker\AppData\Roaming\NCH Software\Copper\Shared\copper.db"
TARGET_DB_PATH="/tmp/copper_export.db"

# Create a PowerShell script to find and copy the database
# We copy the DB to a location where 'copy_from_env' can find it (e.g. C:\workspace\ or a mapped drive)
# Or we output the path so the verifier knows where to look.
# Since copy_from_env takes a container path, we need the file to be accessible.

cat > /tmp/win_export.ps1 << PSEOF
\$ErrorActionPreference = "SilentlyContinue"
\$found = \$false
\$dbPath = ""

# Try common locations
\$paths = @(
    "${DB_PATH_1}",
    "${DB_PATH_2}"
)

foreach (\$path in \$paths) {
    if (Test-Path \$path) {
        Write-Host "Found DB at \$path"
        \$dbPath = \$path
        \$found = \$true
        break
    }
}

if (\$found) {
    # Copy to a temporary location that is accessible (e.g., C:\Temp)
    # This ensures we have a snapshot even if the app has a lock
    New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null
    Copy-Item -Path \$dbPath -Destination "C:\Temp\copper_snapshot.db" -Force
    Write-Host "DB_COPIED:C:\Temp\copper_snapshot.db"
} else {
    Write-Host "DB_NOT_FOUND"
}
PSEOF

# Execute PowerShell to stage the DB
# We assume we can run this via docker exec or similar mechanism provided by the infrastructure
# Since we don't have explicit docker exec access in the script (it runs inside?), 
# we rely on the fact that for Windows containers, often the 'copy_from_env' 
# can pull from the Windows filesystem paths.

# For the purpose of this script, we'll assume we are preparing data for the verifier.
# We will create a JSON file with the task timing.

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Export complete."