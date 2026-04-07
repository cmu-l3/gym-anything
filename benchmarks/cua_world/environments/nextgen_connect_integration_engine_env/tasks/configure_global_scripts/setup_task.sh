#!/bin/bash
echo "=== Setting up Configure Global Scripts task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for NextGen Connect API
echo "Waiting for NextGen Connect API..."
wait_for_api 120 || {
    echo "WARNING: API not ready, continuing anyway"
}

# Reset Global Scripts to Default/Empty state to ensure a clean start
echo "Resetting global scripts to default..."
DEFAULT_SCRIPTS='<map>
  <entry>
    <string>Deploy</string>
    <string>// This script executes once when all channels start up from a deployment
// You only have access to the globalMap here
return;</string>
  </entry>
  <entry>
    <string>Undeploy</string>
    <string>// This script executes once when all channels shut down from an undeployment
// You only have access to the globalMap here
return;</string>
  </entry>
  <entry>
    <string>Preprocessor</string>
    <string>// Modify the message variable below to pre process data
return message;</string>
  </entry>
  <entry>
    <string>Postprocessor</string>
    <string>// This script executes once after a message has been processed
return;</string>
  </entry>
</map>'

curl -sk -X PUT -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Content-Type: application/xml" \
    -d "$DEFAULT_SCRIPTS" \
    "https://localhost:8443/api/server/globalScripts" 2>/dev/null

# Capture initial state hash for verification
echo "$DEFAULT_SCRIPTS" > /tmp/initial_global_scripts.xml
md5sum /tmp/initial_global_scripts.xml | awk '{print $1}' > /tmp/initial_scripts_hash.txt

# Ensure Firefox is open to the landing page (provides context)
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open a terminal for the agent to use curl/python
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "========================================================"
echo " NextGen Connect Global Script Configuration"
echo "========================================================"
echo " API Endpoint: https://localhost:8443/api/server/globalScripts"
echo " Method: PUT (to update), GET (to view)"
echo " Auth: admin / admin"
echo " Header: X-Requested-With: OpenAPI"
echo " Format: XML"
echo "========================================================"
exec bash
' 2>/dev/null &

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="