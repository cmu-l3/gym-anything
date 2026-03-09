#!/bin/bash
echo "=== Exporting segment_tech_holdings result ==="

# 1. Close JStock gracefully to ensure data is saved to disk
# JStock saves on exit.
pkill -f "jstock.jar"
sleep 3

# 2. Define Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_ROOT="${JSTOCK_DATA_DIR}/portfolios"
MY_PORTFOLIO_CSV="${PORTFOLIO_ROOT}/My Portfolio/buyportfolio.csv"
TECH_PORTFOLIO_CSV="${PORTFOLIO_ROOT}/Tech Portfolio/buyportfolio.csv"

# 3. Read File Contents (if they exist)
MY_PORTFOLIO_CONTENT=""
if [ -f "$MY_PORTFOLIO_CSV" ]; then
    MY_PORTFOLIO_CONTENT=$(cat "$MY_PORTFOLIO_CSV" | base64 -w 0)
fi

TECH_PORTFOLIO_CONTENT=""
TECH_PORTFOLIO_EXISTS="false"
if [ -f "$TECH_PORTFOLIO_CSV" ]; then
    TECH_PORTFOLIO_EXISTS="true"
    TECH_PORTFOLIO_CONTENT=$(cat "$TECH_PORTFOLIO_CSV" | base64 -w 0)
fi

# 4. Anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TECH_MOD_TIME=$(stat -c %Y "$TECH_PORTFOLIO_CSV" 2>/dev/null || echo "0")
MY_PORT_MOD_TIME=$(stat -c %Y "$MY_PORTFOLIO_CSV" 2>/dev/null || echo "0")

# 5. Take final screenshot (even though app is closed, capture desktop state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "my_portfolio_content_b64": "$MY_PORTFOLIO_CONTENT",
    "tech_portfolio_content_b64": "$TECH_PORTFOLIO_CONTENT",
    "tech_portfolio_exists": $TECH_PORTFOLIO_EXISTS,
    "task_start_time": $TASK_START,
    "tech_mod_time": $TECH_MOD_TIME,
    "my_port_mod_time": $MY_PORT_MOD_TIME
}
EOF

# 7. Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"