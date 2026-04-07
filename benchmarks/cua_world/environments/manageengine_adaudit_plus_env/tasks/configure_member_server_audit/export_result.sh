#!/bin/bash
set -e
echo "=== Exporting configure_member_server_audit results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$screen = [System.Windows.Forms.Screen]::PrimaryScreen
    \$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
    \$bitmap.Save('C:\\Users\\Public\\task_final.png')
" 2>/dev/null || true

if [ -f "/c/Users/Public/task_final.png" ]; then
    cp "/c/Users/Public/task_final.png" /tmp/task_final.png
fi

# 2. Verify Server Configuration via Database/API/Files
# We'll use PowerShell to query the PostgreSQL database included with ADAudit Plus
# Default DB info: Port 33307, User: postgres, DB: adap
echo "Querying database for server configuration..."

# Create a SQL query file
cat > /tmp/query_server.sql <<EOF
SELECT * FROM "DomainServer" WHERE "DNS_NAME" = 'APP-SERVER-01' OR "DNS_NAME" = 'app-server-01';
EOF

# Execute query using pgsql tool included in ManageEngine (path may vary, using relative or standard path)
# Assuming typical installation path for ManageEngine ADAudit Plus
PG_BIN="/c/Program Files/ManageEngine/ADAudit Plus/pgsql/bin/psql.exe"
DB_PORT="33307" 
DB_USER="postgres"
DB_NAME="adap"

SERVER_FOUND="false"
CONFIG_JSON="{}"

if [ -f "$PG_BIN" ]; then
    # We try to query the DB. Note: Password might be required or trusted local.
    # Often locally it is trusted.
    RESULT=$("$PG_BIN" -U $DB_USER -p $DB_PORT -d $DB_NAME -f /tmp/query_server.sql 2>/dev/null || true)
    
    if echo "$RESULT" | grep -qi "APP-SERVER-01"; then
        SERVER_FOUND="true"
    fi
else
    # Fallback: Check config files or logs if DB access fails
    echo "Postgres binary not found, checking logs/config files..."
    # Check for recent addition in logs
    LOG_DIR="/c/Program Files/ManageEngine/ADAudit Plus/logs"
    if grep -r "APP-SERVER-01" "$LOG_DIR" | grep -q "Added"; then
        SERVER_FOUND="true"
    fi
fi

# 3. Create Result JSON
# We populate this with what we found. The verifier will interpret it.
# We also include timestamps to ensure the entry is new.

cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "server_found": $SERVER_FOUND,
    "screenshot_path": "/tmp/task_final.png",
    "db_query_attempted": $(if [ -f "$PG_BIN" ]; then echo "true"; else echo "false"; fi)
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="