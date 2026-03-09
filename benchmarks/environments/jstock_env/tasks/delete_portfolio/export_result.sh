#!/bin/bash
echo "=== Exporting delete_portfolio results ==="

# Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_ROOT="${JSTOCK_DATA_DIR}/portfolios"
TARGET_DIR="${PORTFOLIO_ROOT}/Speculative Trades"
PRESERVED_DIR="${PORTFOLIO_ROOT}/My Portfolio"

# 1. Capture Final Screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check Directory Existence
if [ -d "$TARGET_DIR" ]; then
    TARGET_EXISTS="true"
else
    TARGET_EXISTS="false"
fi

if [ -d "$PRESERVED_DIR" ]; then
    PRESERVED_EXISTS="true"
else
    PRESERVED_EXISTS="false"
fi

# 3. Check Preserved Data Integrity (Anti-Gaming)
PRESERVED_INTEGRITY="false"
if [ -f "${PRESERVED_DIR}/buyportfolio.csv" ]; then
    # Check if AAPL, MSFT, NVDA are still in the file
    if grep -q "AAPL" "${PRESERVED_DIR}/buyportfolio.csv" && \
       grep -q "MSFT" "${PRESERVED_DIR}/buyportfolio.csv" && \
       grep -q "NVDA" "${PRESERVED_DIR}/buyportfolio.csv"; then
        PRESERVED_INTEGRITY="true"
    fi
fi

# 4. Check modification timestamps (Anti-Gaming)
# The parent 'portfolios' directory mtime changes when a subdir is deleted
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PORTFOLIO_ROOT_MTIME=$(stat -c %Y "$PORTFOLIO_ROOT" 2>/dev/null || echo "0")

if [ "$PORTFOLIO_ROOT_MTIME" -gt "$TASK_START" ]; then
    FS_MODIFIED="true"
else
    FS_MODIFIED="false"
fi

# 5. Count Remaining Portfolios
FINAL_COUNT=$(ls -1 "$PORTFOLIO_ROOT" 2>/dev/null | wc -l)
INITIAL_COUNT=$(cat /tmp/initial_portfolio_count.txt 2>/dev/null || echo "0")

# 6. Check if App is Running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 7. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_exists": $TARGET_EXISTS,
    "preserved_exists": $PRESERVED_EXISTS,
    "preserved_integrity": $PRESERVED_INTEGRITY,
    "filesystem_modified_during_task": $FS_MODIFIED,
    "initial_portfolio_count": $INITIAL_COUNT,
    "final_portfolio_count": $FINAL_COUNT,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="