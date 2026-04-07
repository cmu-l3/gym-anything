#!/bin/bash
# Export script for Audit Patient Eligibility task
# Collects ground truth from VistA to verify agent's visual output

echo "=== Exporting Audit Patient Eligibility Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "$1" 2>/dev/null || true
    }
fi

# Fallback escape_json
if ! type escape_json &>/dev/null; then
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# VistA Status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi

# YDBGui Access
YDBGUI_ACCESSIBLE="false"
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
if [ -n "$CONTAINER_IP" ]; then
    if curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null | grep -q "200"; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Browser Window
BROWSER_OPEN="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui"; then
    BROWSER_OPEN="true"
fi

# =============================================================================
# EXTRACT GROUND TRUTH FROM DATABASE
# =============================================================================
# We need to find the actual names for Period of Service and Eligibility for DFN 1
# Logic:
# 1. Get pointer from ^DPT(1,.32) piece 3 -> Service IEN
# 2. Get name from ^DIC(21,Service_IEN,0) piece 1
# 3. Get pointer from ^DPT(1,.36) piece 1 -> Eligibility IEN
# 4. Get name from ^DIC(8,Eligibility_IEN,0) piece 1

GT_SERVICE_NAME=""
GT_ELIGIBILITY_NAME=""

if [ "$VISTA_STATUS" = "running" ]; then
    echo "Querying Ground Truth..."
    
    # Run M script inside container to resolve pointers
    # Use strict output formatting to parse easily
    GT_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "
    S DFN=1
    S SVCptr=\$P(\$G(^DPT(DFN,.32)),U,3)
    S ELIGptr=\$P(\$G(^DPT(DFN,.36)),U,1)
    S SVCname=\"\" S:SVCptr]\"\" SVCname=\$P(\$G(^DIC(21,SVCptr,0)),U,1)
    S ELIGname=\"\" S:ELIGptr]\"\" ELIGname=\$P(\$G(^DIC(8,ELIGptr,0)),U,1)
    W \"SERVICE:\",SVCname,\"|ELIGIBILITY:\",ELIGname
    "' 2>/dev/null | tail -1)
    
    # Parse output: SERVICE:Name|ELIGIBILITY:Name
    GT_SERVICE_NAME=$(echo "$GT_DATA" | sed -n 's/.*SERVICE:\([^|]*\)|.*/\1/p')
    GT_ELIGIBILITY_NAME=$(echo "$GT_DATA" | sed -n 's/.*ELIGIBILITY:\(.*\)/\1/p')
    
    echo "Ground Truth Found:"
    echo "  Service: $GT_SERVICE_NAME"
    echo "  Eligibility: $GT_ELIGIBILITY_NAME"
fi

# Escape for JSON
GT_SERVICE_ESC=$(escape_json "$GT_SERVICE_NAME")
GT_ELIGIBILITY_ESC=$(escape_json "$GT_ELIGIBILITY_NAME")

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "ground_truth": {
        "service_name": "$GT_SERVICE_ESC",
        "eligibility_name": "$GT_ELIGIBILITY_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result JSON saved."
echo "=== Export Complete ==="