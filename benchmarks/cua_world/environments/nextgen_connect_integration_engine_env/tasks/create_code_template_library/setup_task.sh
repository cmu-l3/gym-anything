#!/bin/bash
echo "=== Setting up create_code_template_library task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for API to be ready
wait_for_api 60

# Record initial count of code template libraries
# Using direct DB query for reliability
INITIAL_LIB_COUNT=$(query_postgres "SELECT COUNT(*) FROM code_template_library;" 2>/dev/null || echo "0")
echo "$INITIAL_LIB_COUNT" > /tmp/initial_lib_count.txt

INITIAL_TEMPLATE_COUNT=$(query_postgres "SELECT COUNT(*) FROM code_template;" 2>/dev/null || echo "0")
echo "$INITIAL_TEMPLATE_COUNT" > /tmp/initial_template_count.txt

echo "Initial State: $INITIAL_LIB_COUNT libraries, $INITIAL_TEMPLATE_COUNT templates"

# Open a terminal window for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - REST API Task"
echo "============================================"
echo ""
echo "TASK: Create Code Template Library & Functions"
echo ""
echo "API Endpoint: https://localhost:8443/api"
echo "Credentials: admin / admin"
echo "Header Required: X-Requested-With: OpenAPI"
echo ""
echo "Goal:"
echo "1. Create Library: \"HL7 Processing Utilities\""
echo "2. Create 3 Functions: formatHL7Date, extractPatientName, generateACK"
echo ""
echo "Tools: curl, python3, vim, nano"
echo "Docs: https://localhost:8443/api (if docs enabled) or standard Mirth Connect docs"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Ensure Firefox is open to the dashboard/landing page (as a visual aid/confirmation tool)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:8443' &"
    sleep 5
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="