#!/bin/bash
echo "=== Exporting Timber Cruise Results ==="

# Define paths
FILE_PATH="C:\\Users\\Docker\\Documents\\timber_cruise.xlsx"
RESULT_JSON="/tmp/task_result.json"

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check file existence and modification
# We use PowerShell to inspect file properties since we are on Windows
powershell.exe -Command "
\$path = '$FILE_PATH'
if (Test-Path \$path) {
    \$item = Get-Item \$path
    \$mtime = \$item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    \$size = \$item.Length
    \$exists = \$true
    
    # Check if modified after task start (Need to pass TASK_START from bash)
    # Simplified: We just return the mtime and let Python verifier compare.
} else {
    \$exists = \$false
    \$mtime = ''
    \$size = 0
}

\$json = @{
    output_exists = \$exists
    output_size_bytes = \$size
    last_modified = \$mtime
    task_start = $TASK_START
    task_end = $TASK_END
    file_path = \$path
} | ConvertTo-Json

\$json | Out-File -FilePath 'C:\\Users\\Docker\\result_meta.json' -Encoding ASCII
"

# Move the meta json to a location we can read (or just cat it)
cp "C:\\Users\\Docker\\result_meta.json" /tmp/result_meta.json 2>/dev/null || true

# 2. Take final screenshot (Framework handles this usually, but we ensure one exists)
# (Skipping explicit scrot command as this is Windows env, relying on framework observation)

# 3. Create Final JSON
# We merge the powershell output with our standard export format
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "metadata_path": "/tmp/result_meta.json",
    "excel_path": "$FILE_PATH"
}
EOF

echo "Export complete. Result at $RESULT_JSON"