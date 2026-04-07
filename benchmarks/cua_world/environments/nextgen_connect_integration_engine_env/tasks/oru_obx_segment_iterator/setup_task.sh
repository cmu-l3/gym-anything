#!/bin/bash
echo "=== Setting up ORU OBX Segment Iterator Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120 || {
    echo "WARNING: API not ready, continuing anyway"
}

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt
echo "Initial channel count: $INITIAL_COUNT"

# Ensure no pre-existing channel with this name
echo "Cleaning up any pre-existing channels..."
EXISTING_ID=$(api_call GET "/channels" 2>/dev/null | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    for ch in root.findall('.//channel'):
        name = ch.find('name')
        cid = ch.find('id')
        if name is not None and cid is not None and 'Lab_Results_OBX_Extractor' in name.text:
            print(cid.text)
except:
    pass
" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Removing pre-existing channel: $EXISTING_ID"
    api_call DELETE "/channels/$EXISTING_ID" 2>/dev/null || true
    sleep 2
fi

# Clean up any existing output files inside the container
docker exec nextgen-connect rm -rf /tmp/lab_results 2>/dev/null || true

# Clean up any output files on the host
rm -rf /tmp/lab_results 2>/dev/null || true

# Ensure port 6661 is not in use by other channels
echo "Checking port 6661 availability..."
if nc -z localhost 6661 2>/dev/null; then
    echo "WARNING: Port 6661 appears to be in use"
fi

# Ensure Firefox is running and showing the landing page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Open a helper terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - OBX Segment Extractor"
echo "============================================"
echo ""
echo "TASK: Create channel Lab_Results_OBX_Extractor"
echo "  - Source: TCP Listener on port 6661 (HL7 v2.x)"
echo "  - Transform: Iterate over OBX segments -> Raw text"
echo "  - Dest: File Writer to /tmp/lab_results/obx_results.txt (append mode)"
echo ""
echo "Output Format (pipe-delimited):"
echo "  SetID|LOINC|Name|Value|Units|RefRange|Abnormal"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Header: X-Requested-With: OpenAPI"
echo ""
echo "Sample MLLP command:"
echo "  printf \"\\x0b...\\x1c\\x0d\" | nc localhost 6661"
echo ""
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="