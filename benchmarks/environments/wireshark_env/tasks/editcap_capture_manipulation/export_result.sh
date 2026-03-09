#!/bin/bash
set -e
echo "=== Exporting editcap capture manipulation result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/captures/output"
GT_FILE="/tmp/task_ground_truth.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load ground truth values (using python to parse the JSON created in setup)
GT_ORIG=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['original_count'])" 2>/dev/null || echo "0")
GT_FIRST_TS=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['first_timestamp'])" 2>/dev/null || echo "0")
GT_PKT50_TS=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['packet_50_timestamp'])" 2>/dev/null || echo "0")
GT_DEDUP=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['dedup_count'])" 2>/dev/null || echo "0")

# Helper function to analyze a capture file
analyze_file() {
    local fpath="$1"
    if [ ! -f "$fpath" ]; then
        echo "{\"exists\": false}"
        return
    fi
    
    local fsize=$(stat -c%s "$fpath")
    local fmtime=$(stat -c%Y "$fpath")
    local created_during_task="false"
    if [ "$fmtime" -gt "$TASK_START" ]; then
        created_during_task="true"
    fi
    
    # Use capinfos for format
    local format=$(capinfos -t "$fpath" 2>/dev/null | grep "File type" | cut -d: -f2- | xargs)
    
    # Use tshark for count and timestamps
    local count=$(tshark -r "$fpath" 2>/dev/null | wc -l)
    local first_ts="0"
    if [ "$count" -gt 0 ]; then
        first_ts=$(tshark -r "$fpath" -T fields -e frame.time_epoch -c 1 2>/dev/null | head -1)
    fi
    
    # Construct JSON object
    cat << EOF
{
    "exists": true,
    "size": $fsize,
    "created_during_task": $created_during_task,
    "format": "$format",
    "packet_count": $count,
    "first_timestamp": "$first_ts"
}
EOF
}

echo "Analyzing output files..."

# Analyze each expected output file
JSON_F100=$(analyze_file "$OUTPUT_DIR/first_100.pcapng")
JSON_RANGE=$(analyze_file "$OUTPUT_DIR/range_50_150.pcapng")
JSON_CONV=$(analyze_file "$OUTPUT_DIR/converted.pcap")
JSON_DEDUP=$(analyze_file "$OUTPUT_DIR/deduped.pcapng")
JSON_SHIFT=$(analyze_file "$OUTPUT_DIR/timeshifted.pcapng")

# Read user's report file if it exists
REPORT_CONTENT="{}"
REPORT_FILE="$OUTPUT_DIR/manipulation_report.json"
REPORT_EXISTS="false"
if [ -f "$REPORT_FILE" ]; then
    # Validate if it's valid JSON
    if python3 -c "import json; json.load(open('$REPORT_FILE'))" >/dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$REPORT_FILE")
        REPORT_EXISTS="true"
    fi
fi

# Compile final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "ground_truth": {
        "original_count": $GT_ORIG,
        "first_timestamp": "$GT_FIRST_TS",
        "packet_50_timestamp": "$GT_PKT50_TS",
        "dedup_count": $GT_DEDUP
    },
    "files": {
        "first_100": $JSON_F100,
        "range_50_150": $JSON_RANGE,
        "converted": $JSON_CONV,
        "deduped": $JSON_DEDUP,
        "timeshifted": $JSON_SHIFT
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "content": $REPORT_CONTENT
    }
}
EOF

# Save to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="