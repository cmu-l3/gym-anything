#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bmp)
    \$graphics.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
    \$bmp.Save('C:\workspace\task_final.png')
    " 2>/dev/null || true

if [ -f "/workspace/task_final.png" ]; then
    mv /workspace/task_final.png /tmp/task_final.png
fi

# 3. Query Database for Final State
# We need to check:
# - Status of Anita Roy's leave (Should be 2/Sanctioned)
# - Status of Rajiv Menon's leave (Should be 1/Applied)

cat > /tmp/check_db.sql << EOF
SET HEAD OFF;
SET LIST ON;
SELECT 
    E.FIRST_NAME, 
    LA.FROM_DATE, 
    LA.STATUS 
FROM LEAVE_APPLICATION LA
JOIN EMPLOYEE E ON LA.EMPLOYEE_ID = E.EMPLOYEE_ID
WHERE E.EMP_CODE IN ('EMP-9001', 'EMP-9002')
AND LA.FROM_DATE IN ('2025-10-15', '2025-10-20');
COMMIT;
EXIT;
EOF

echo "Querying database..."
DB_OUTPUT_FILE="/tmp/db_result.txt"

powershell.exe -Command "
    \$isql = 'C:\Program Files\Firebird\Firebird_3_0\isql.exe'
    if (-not (Test-Path \$isql)) { \$isql = 'C:\Program Files (x86)\Firebird\Firebird_3_0\isql.exe' }
    
    \$dbPath = Get-ChildItem -Path 'C:\Program Files\Lenvica\AttendHRM' -Filter '*.fdb' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (-not \$dbPath) { \$dbPath = Get-ChildItem -Path 'C:\Program Files (x86)\Lenvica\AttendHRM' -Filter '*.fdb' -Recurse | Select-Object -First 1 -ExpandProperty FullName }
    
    if (\$dbPath) {
        \$sqlCmd = Get-Content -Path '/tmp/check_db.sql' -Raw
        \$sqlCmd | & \$isql -user SYSDBA -password masterkey \$dbPath | Out-File -FilePath 'C:\workspace\db_output.txt' -Encoding UTF8
    }
" 2>/dev/null || true

# Move output file if generated
if [ -f "/workspace/db_output.txt" ]; then
    mv /workspace/db_output.txt "$DB_OUTPUT_FILE"
fi

# 4. Parse DB Output
# Expected output format from ISQL LIST ON:
# FIRST_NAME                      Anita
# FROM_DATE                       2025-10-15
# STATUS                          2
# ...

ANITA_STATUS="-1"
RAJIV_STATUS="-1"

if [ -f "$DB_OUTPUT_FILE" ]; then
    # Simple parsing logic
    # We look for blocks. 
    # Anita's block
    ANITA_BLOCK=$(grep -A 5 "Anita" "$DB_OUTPUT_FILE" || echo "")
    ANITA_STATUS=$(echo "$ANITA_BLOCK" | grep "STATUS" | awk '{print $2}')
    
    # Rajiv's block
    RAJIV_BLOCK=$(grep -A 5 "Rajiv" "$DB_OUTPUT_FILE" || echo "")
    RAJIV_STATUS=$(echo "$RAJIV_BLOCK" | grep "STATUS" | awk '{print $2}')
fi

# 5. Check if App Running
APP_RUNNING=$(powershell.exe -Command "if (Get-Process -Name 'AttendHRM*' -ErrorAction SilentlyContinue) { Write-Host 'true' } else { Write-Host 'false' }" | tr -d '\r\n')

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": "$APP_RUNNING",
    "anita_status": "$ANITA_STATUS",
    "rajiv_status": "$RAJIV_STATUS",
    "screenshot_path": "/tmp/task_final.png",
    "db_output_raw": "$(cat $DB_OUTPUT_FILE | tr -d '\n' | sed 's/"/\\"/g' 2>/dev/null)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"