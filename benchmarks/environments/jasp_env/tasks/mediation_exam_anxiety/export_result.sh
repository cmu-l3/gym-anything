#!/bin/bash
echo "=== Exporting Mediation Task Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
PROJECT_FILE="/home/ga/Documents/JASP/MediationAnalysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/mediation_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check JASP Project File
PROJECT_EXISTS="false"
PROJECT_MODIFIED="false"
PROJECT_SIZE="0"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$PROJECT_MTIME" -gt "$START_TIME" ]; then
        PROJECT_MODIFIED="true"
    fi
    
    # Copy to /tmp for verifier access
    cp "$PROJECT_FILE" /tmp/MediationAnalysis.jasp
    chmod 666 /tmp/MediationAnalysis.jasp
fi

# 4. Check Report File
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -gt "$START_TIME" ]; then
        REPORT_MODIFIED="true"
    fi
    
    # Copy to /tmp for verifier access
    cp "$REPORT_FILE" /tmp/mediation_report.txt
    chmod 666 /tmp/mediation_report.txt
fi

# 5. Check if JASP is still running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $START_TIME,
    "project_exists": $PROJECT_EXISTS,
    "project_modified": $PROJECT_MODIFIED,
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_modified": $REPORT_MODIFIED,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json