#!/bin/bash
echo "=== Exporting create_investigation_form results ==="

# Paths
TASK_START_FILE="/tmp/task_start_time.txt"
PROJECT_FILE_WIN="C:\\Users\\Docker\\Documents\\Epi Info 7\\Projects\\NorovirusOutbreak\\NorovirusOutbreak.prj"
PROJECT_FILE_BASH="/c/Users/Docker/Documents/Epi Info 7/Projects/NorovirusOutbreak/NorovirusOutbreak.prj"

# Get start time
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if Project File Exists
PRJ_EXISTS="false"
PRJ_SIZE=0
PRJ_CONTENT=""

if [ -f "$PROJECT_FILE_BASH" ]; then
    PRJ_EXISTS="true"
    PRJ_SIZE=$(stat -c %s "$PROJECT_FILE_BASH")
    # Read content for verification (safe to read text XML)
    PRJ_CONTENT=$(cat "$PROJECT_FILE_BASH" | tr -d '\0') # Remove null bytes just in case
fi

# 2. Check File Timestamp (Anti-Gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$PRJ_EXISTS" == "true" ]; then
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE_BASH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check for Database File (MDB or SDF)
DB_EXISTS="false"
if ls "/c/Users/Docker/Documents/Epi Info 7/Projects/NorovirusOutbreak/"*.mdb 1> /dev/null 2>&1 || \
   ls "/c/Users/Docker/Documents/Epi Info 7/Projects/NorovirusOutbreak/"*.sdf 1> /dev/null 2>&1; then
    DB_EXISTS="true"
fi

# 4. Capture Final Screenshot
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\\workspace\\task_final.png')
"

# 5. Create JSON Result
# We embed the PRJ content into the JSON for the verifier to parse
# Escape quotes in content for JSON safety
SAFE_CONTENT=$(echo "$PRJ_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prj_exists": $PRJ_EXISTS,
    "prj_size_bytes": $PRJ_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_exists": $DB_EXISTS,
    "prj_content_sample": "${SAFE_CONTENT:0:50000}", 
    "screenshot_path": "C:\\workspace\\task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="