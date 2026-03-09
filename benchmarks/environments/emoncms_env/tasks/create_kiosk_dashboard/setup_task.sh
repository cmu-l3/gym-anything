#!/bin/bash
set -e
echo "=== Setting up Create Kiosk Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# -----------------------------------------------------------------------
# 1. Create Target Dashboards
# -----------------------------------------------------------------------
echo "Creating target dashboards..."

# Function to create a dashboard if it doesn't exist
create_target_dashboard() {
    local name="$1"
    local desc="$2"
    local alias="$3"
    
    # Check if exists
    local exists=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -s -e "SELECT id FROM dashboard WHERE name='$name'" 2>/dev/null)
    
    if [ -z "$exists" ]; then
        # Create via SQL for speed and reliability in setup
        # User ID 1 is admin
        local sql="INSERT INTO dashboard (userid, name, description, alias, public, published, content) VALUES (1, '$name', '$desc', '$alias', 0, 1, '[]');"
        docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "$sql" 2>/dev/null
        echo "Created dashboard: $name"
    else
        echo "Dashboard already exists: $name"
    fi
}

# Create the three specific dashboards the agent needs to find
create_target_dashboard "Solar Array A" "Main generation metrics" "solar-array-a"
create_target_dashboard "HVAC Main" "Heating and Cooling status" "hvac-main"
create_target_dashboard "Lighting Zones" "Interior lighting controls" "lighting-zones"

# Ensure "Facility Kiosk" does NOT exist (clean state)
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "DELETE FROM dashboard WHERE name='Facility Kiosk'" 2>/dev/null || true

# -----------------------------------------------------------------------
# 2. Launch Firefox
# -----------------------------------------------------------------------
# Start Firefox on the dashboard list page so agent sees the targets immediately
echo "Launching Firefox to dashboard list..."
launch_firefox_to "http://localhost/dashboard/list" 5

# -----------------------------------------------------------------------
# 3. Capture Initial State
# -----------------------------------------------------------------------
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="