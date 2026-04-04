#!/bin/bash
echo "=== Exporting track_dca_position results ==="

# Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
DCA_PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/DCA Strategy"
BUY_CSV="${DCA_PORTFOLIO_DIR}/buyportfolio.csv"
SUMMARY_FILE="/home/ga/dca_summary.txt"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get Timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
NOW=$(date +%s)

# 3. Check Portfolio Directory
PORTFOLIO_EXISTS="false"
PORTFOLIO_MTIME="0"
if [ -d "$DCA_PORTFOLIO_DIR" ]; then
    PORTFOLIO_EXISTS="true"
    PORTFOLIO_MTIME=$(stat -c %Y "$DCA_PORTFOLIO_DIR" 2>/dev/null || echo "0")
fi

# 4. Check Buy CSV
CSV_EXISTS="false"
CSV_CONTENT=""
CSV_MTIME="0"
if [ -f "$BUY_CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$BUY_CSV" 2>/dev/null || echo "0")
    # Read CSV content, base64 encode to avoid JSON escaping issues
    CSV_CONTENT=$(base64 -w 0 "$BUY_CSV")
fi

# 5. Check Summary File
SUMMARY_EXISTS="false"
SUMMARY_CONTENT=""
SUMMARY_MTIME="0"
if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    SUMMARY_CONTENT=$(base64 -w 0 "$SUMMARY_FILE")
fi

# 6. Check if "My Portfolio" still exists (sanity check)
DEFAULT_EXISTS="false"
if [ -d "${JSTOCK_DATA_DIR}/portfolios/My Portfolio" ]; then
    DEFAULT_EXISTS="true"
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_time": $NOW,
    "portfolio_exists": $PORTFOLIO_EXISTS,
    "portfolio_mtime": $PORTFOLIO_MTIME,
    "csv_exists": $CSV_EXISTS,
    "csv_mtime": $CSV_MTIME,
    "csv_content_b64": "$CSV_CONTENT",
    "summary_exists": $SUMMARY_EXISTS,
    "summary_mtime": $SUMMARY_MTIME,
    "summary_content_b64": "$SUMMARY_CONTENT",
    "default_portfolio_preserved": $DEFAULT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="