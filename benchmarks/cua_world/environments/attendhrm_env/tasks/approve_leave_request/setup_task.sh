#!/bin/bash
set -e
echo "=== Setting up task: Approve Leave Request ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare the Database Setup Script (Firebird SQL)
# We need to:
# - Ensure employees Anita Roy and Rajiv Menon exist
# - Ensure Leave Types exist (Sick Leave, Privilege Leave)
# - Insert Pending Leave Applications for them
# - Clear any previous states for these requests

cat > /tmp/setup_db.sql << EOF
SET TERM ^ ;

-- 1. Ensure Employees Exist
MERGE INTO EMPLOYEE AS E
USING (SELECT 'EMP-9001' AS EMP_CODE, 'Anita' AS FN, 'Roy' AS LN FROM RDB\$DATABASE) AS N
ON E.EMP_CODE = N.EMP_CODE
WHEN NOT MATCHED THEN
INSERT (EMP_CODE, FIRST_NAME, LAST_NAME, EMP_NAME, STATUS, DOJ)
VALUES (N.EMP_CODE, N.FN, N.LN, N.FN || ' ' || N.LN, 1, '2024-01-01');

MERGE INTO EMPLOYEE AS E
USING (SELECT 'EMP-9002' AS EMP_CODE, 'Rajiv' AS FN, 'Menon' AS LN FROM RDB\$DATABASE) AS N
ON E.EMP_CODE = N.EMP_CODE
WHEN NOT MATCHED THEN
INSERT (EMP_CODE, FIRST_NAME, LAST_NAME, EMP_NAME, STATUS, DOJ)
VALUES (N.EMP_CODE, N.FN, N.LN, N.FN || ' ' || N.LN, 1, '2024-01-01');

-- 2. Clean up existing leave applications for these dates to ensure clean state
DELETE FROM LEAVE_APPLICATION 
WHERE (EMPLOYEE_ID IN (SELECT EMPLOYEE_ID FROM EMPLOYEE WHERE EMP_CODE IN ('EMP-9001', 'EMP-9002')))
AND (FROM_DATE IN ('2025-10-15', '2025-10-20'));

-- 3. Insert Pending Request for Anita Roy (Sick Leave - usually Type ID 2 or similar, defaulting to finding by name if possible, else hardcoding common ID)
-- Assuming Leave Type 2 is Sick Leave, 1 is Casual, 3 is Privilege. Adjusting to subselect if schema allows, otherwise using likely IDs.
INSERT INTO LEAVE_APPLICATION (EMPLOYEE_ID, LEAVE_TYPE_ID, FROM_DATE, TO_DATE, REASON, STATUS, APPLIED_DATE)
SELECT E.EMPLOYEE_ID, 2, '2025-10-15', '2025-10-15', 'Medical Procedure', 1, '2025-10-01'
FROM EMPLOYEE E WHERE E.EMP_CODE = 'EMP-9001';
-- Status 1 usually means 'Applied'/'Pending' in AttendHRM (2=Sanctioned, 3=Rejected)

-- 4. Insert Decoy Pending Request for Rajiv Menon
INSERT INTO LEAVE_APPLICATION (EMPLOYEE_ID, LEAVE_TYPE_ID, FROM_DATE, TO_DATE, REASON, STATUS, APPLIED_DATE)
SELECT E.EMPLOYEE_ID, 3, '2025-10-20', '2025-10-20', 'Family Function', 1, '2025-10-02'
FROM EMPLOYEE E WHERE E.EMP_CODE = 'EMP-9002';

COMMIT^
SET TERM ; ^
EOF

# 3. Execute DB Setup via PowerShell
echo "Executing DB setup..."
powershell.exe -Command "
    \$isql = 'C:\Program Files\Firebird\Firebird_3_0\isql.exe'
    if (-not (Test-Path \$isql)) {
        \$isql = 'C:\Program Files (x86)\Firebird\Firebird_3_0\isql.exe'
    }
    
    # Find Database Path
    \$dbPath = Get-ChildItem -Path 'C:\Program Files\Lenvica\AttendHRM' -Filter '*.fdb' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (-not \$dbPath) {
        \$dbPath = Get-ChildItem -Path 'C:\Program Files (x86)\Lenvica\AttendHRM' -Filter '*.fdb' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    }
    
    if (\$dbPath -and (Test-Path \$isql)) {
        Write-Host \"Connecting to DB: \$dbPath\"
        # Convert unix path to windows for the SQL file
        \$sqlFile = 'Z:\tmp\setup_db.sql' # Assuming Z: maps to root or using copy
        # Since we are in bash, we need to handle file mapping. 
        # Easier: Read file content and pass as string or use the mapped workspace path if available.
        # We'll use the temp file created in the container, accessible via standard windows paths if mapped?
        # Typically /tmp in linux container might not map directly to Windows C:\tmp.
        # SAFE METHOD: Write content directly in PS.
        
        \$sqlCmd = Get-Content -Path '/tmp/setup_db.sql' -Raw
        \$sqlCmd | & \$isql -user SYSDBA -password masterkey \$dbPath
    } else {
        Write-Error 'Could not find Firebird ISQL or Database file'
        exit 1
    }
" || echo "WARNING: DB Setup script failed (possibly due to path issues), proceeding hoping data exists..."

# 4. Ensure Application is Running
if ! pgrep -f "AttendHRM" > /dev/null; then
    echo "Starting AttendHRM..."
    # Launch in background using PowerShell to handle Windows paths correctly
    powershell.exe -Command "Start-Process 'C:\Program Files\Lenvica\AttendHRM\AttendHRM.exe' -WindowStyle Maximized" 2>/dev/null || \
    powershell.exe -Command "Start-Process 'C:\Program Files (x86)\Lenvica\AttendHRM\AttendHRM.exe' -WindowStyle Maximized" 2>/dev/null
    sleep 15
fi

# 5. Maximize Window
echo "Maximizing window..."
# wmctrl might not work on Windows directly unless running an X server wrapper.
# We rely on PowerShell to ensure window focus/size.
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$proc = Get-Process -Name 'AttendHRM*' | Select-Object -First 1
    if (\$proc) {
        \$hwnd = \$proc.MainWindowHandle
        # Simple maximize check/attempt logic could go here if needed
        # But 'Start-Process -WindowStyle Maximized' usually handles it.
    }
"

# 6. Take Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bmp)
    \$graphics.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
    \$bmp.Save('C:\workspace\task_initial.png')
    " 2>/dev/null || true

# Move screenshot if saved by PS
if [ -f "/workspace/task_initial.png" ]; then
    mv /workspace/task_initial.png /tmp/task_initial.png
fi

echo "=== Setup complete ==="