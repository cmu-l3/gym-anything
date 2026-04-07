#!/bin/bash
# Export script for inventory_supply_chain_traceability
# Reads the agent's report file and exports it alongside the ground truth.

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for Report File
REPORT_PATH="/home/ga/Desktop/investigation_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
fi

# 3. Load Ground Truth (hidden from agent)
TRUTH_FILE="/tmp/traceability_truth.json"
if [ -f "$TRUTH_FILE" ]; then
    TRUTH_CONTENT=$(cat "$TRUTH_FILE")
else
    TRUTH_CONTENT="{}"
fi

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "ground_truth": $TRUTH_CONTENT,
    "timestamp": "$(date +%s)"
}
EOF

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"