#!/bin/bash
# Setup script for Report Crop Incident task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Report Crop Incident Task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Ekylibre to be fully ready
wait_for_ekylibre 120
EKYLIBRE_URL=$(detect_ekylibre_url)

# 3. Record initial state (Incident count)
# We query the incidents table. Note: Schema might be tenant-specific.
# We assume the default tenant or search path is set correctly by the docker exec user or standard setup.
# In Ekylibre, incidents are often stored in 'incidents' table.
echo "Recording initial incident count..."
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM incidents" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_incident_count.txt
echo "Initial incidents: $INITIAL_COUNT"

# 4. Ensure Firefox is open and logged in
# We start at the Dashboard to force navigation
ensure_firefox_with_ekylibre "$EKYLIBRE_URL/backend"
sleep 5

# 5. Maximize window for better VLM visibility
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="