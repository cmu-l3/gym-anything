#!/bin/bash
echo "=== Exporting edit_portfolio_transaction result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PORTFOLIO_CSV="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# Check file stats
if [ -f "$PORTFOLIO_CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$PORTFOLIO_CSV" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c %s "$PORTFOLIO_CSV" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
    
    # Copy the portfolio file to /tmp for easy access by verifier
    # (Handling permissions so verifier running as root/user can read it)
    cp "$PORTFOLIO_CSV" /tmp/final_buyportfolio.csv
    chmod 666 /tmp/final_buyportfolio.csv
else
    CSV_EXISTS="false"
    MODIFIED_DURING_TASK="false"
    CSV_MTIME="0"
    CSV_SIZE="0"
fi

# Take final screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $MODIFIED_DURING_TASK,
    "csv_mtime": $CSV_MTIME,
    "csv_size": $CSV_SIZE,
    "portfolio_path": "$PORTFOLIO_CSV",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"