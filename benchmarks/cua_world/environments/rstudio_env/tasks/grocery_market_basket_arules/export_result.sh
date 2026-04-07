#!/bin/bash
echo "=== Exporting Market Basket Analysis Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
OUT_DIR="/home/ga/RProjects/output"
FREQ_CSV="$OUT_DIR/item_frequencies.csv"
RULES_CSV="$OUT_DIR/top_association_rules.csv"
MILK_CSV="$OUT_DIR/wholemilk_rules.csv"
NET_PNG="$OUT_DIR/rules_network.png"
SCRIPT="$OUT_DIR/../market_basket_analysis.R"

# Function to check file status
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "old|$size"
        fi
    else
        echo "false|0"
    fi
}

# Check files
IFS='|' read FREQ_EXISTS FREQ_SIZE <<< $(check_file "$FREQ_CSV")
IFS='|' read RULES_EXISTS RULES_SIZE <<< $(check_file "$RULES_CSV")
IFS='|' read MILK_EXISTS MILK_SIZE <<< $(check_file "$MILK_CSV")
IFS='|' read PNG_EXISTS PNG_SIZE <<< $(check_file "$NET_PNG")
IFS='|' read SCRIPT_EXISTS SCRIPT_SIZE <<< $(check_file "$SCRIPT")

# Check if arules was installed during task
ARULES_INSTALLED="false"
if [ -d "/home/ga/R/library/arules" ]; then
    LIB_MTIME=$(stat -c %Y "/home/ga/R/library/arules" 2>/dev/null || echo "0")
    if [ "$LIB_MTIME" -gt "$TASK_START" ]; then
        ARULES_INSTALLED="true"
    fi
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "freq_csv": {
        "exists": "$FREQ_EXISTS",
        "size": $FREQ_SIZE,
        "path": "$FREQ_CSV"
    },
    "rules_csv": {
        "exists": "$RULES_EXISTS",
        "size": $RULES_SIZE,
        "path": "$RULES_CSV"
    },
    "milk_csv": {
        "exists": "$MILK_EXISTS",
        "size": $MILK_SIZE,
        "path": "$MILK_CSV"
    },
    "network_png": {
        "exists": "$PNG_EXISTS",
        "size": $PNG_SIZE,
        "path": "$NET_PNG"
    },
    "script": {
        "exists": "$SCRIPT_EXISTS",
        "size": $SCRIPT_SIZE
    },
    "arules_installed_during_task": $ARULES_INSTALLED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="