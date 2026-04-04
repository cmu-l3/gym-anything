#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# Take final screenshot BEFORE closing app (to show work in UI)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || true

# Check if app was running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
    echo "JStock is running. Closing gracefully to force save..."
    
    # Try to close gracefully via Window Manager to trigger save
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -c "JStock"
    
    # Wait for save and exit
    for i in {1..10}; do
        if ! pgrep -f "jstock.jar" > /dev/null; then
            break
        fi
        sleep 1
    done
    
    # Force kill if still running
    if pgrep -f "jstock.jar" > /dev/null; then
        echo "Force killing JStock..."
        pkill -f "jstock.jar"
        sleep 2
    fi
else
    echo "JStock was not running."
fi

# Check file modification
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$PORTFOLIO_FILE")
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy JSON to shared location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the portfolio CSV to tmp for the verifier to read
rm -f /tmp/buyportfolio.csv
if [ -f "$PORTFOLIO_FILE" ]; then
    cp "$PORTFOLIO_FILE" /tmp/buyportfolio.csv
    chmod 666 /tmp/buyportfolio.csv
fi

echo "Export complete. Result at /tmp/task_result.json, Data at /tmp/buyportfolio.csv"