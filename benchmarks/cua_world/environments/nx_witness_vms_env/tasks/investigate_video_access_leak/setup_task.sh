#!/bin/bash
set -e
echo "=== Setting up Investigate Video Access Leak task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. SETUP CAMERAS
echo "Configuring camera names..."
# Rename a camera to "Secure Lab Camera" to be the target
CAM1_ID=$(get_camera_id_by_name "Parking Lot Camera")
if [ -z "$CAM1_ID" ]; then CAM1_ID=$(get_first_camera_id); fi

if [ -n "$CAM1_ID" ]; then
    echo "Target Camera ID: $CAM1_ID"
    nx_api_patch "/rest/v1/devices/${CAM1_ID}" '{"name": "Secure Lab Camera"}'
fi

# Rename another camera to be a decoy
CAM2_ID=$(get_camera_id_by_name "Entrance Camera")
if [ -n "$CAM2_ID" ]; then
    nx_api_patch "/rest/v1/devices/${CAM2_ID}" '{"name": "Lobby Camera"}'
fi

# 2. CREATE USERS
echo "Creating scenario users..."
USERS=("john.smith" "sarah.connor" "rick.deckard" "ellen.ripley" "james.bond")
# Randomly select one suspect
SUSPECT=${USERS[$((RANDOM % ${#USERS[@]}))]}

# Save ground truth in a location inaccessible to the agent (root owned)
echo "$SUSPECT" > /root/ground_truth_suspect.txt
chmod 600 /root/ground_truth_suspect.txt

# Create all users
for user in "${USERS[@]}"; do
    # Create user with Viewer role (roleId typically needed, or use preset)
    # Using simple creation; permissions might default or need setting
    # We give them enough permissions to view cameras
    nx_api_post "/rest/v1/users" "{
        \"name\": \"$user\",
        \"password\": \"Password123!\",
        \"userRoleId\": \"00000000-0000-0000-0000-000000000002\", 
        \"permissions\": \"GlobalView\"
    }" > /dev/null 2>&1 || true
    echo "Created user: $user"
done

# Wait for users to sync
sleep 3

# 3. GENERATE AUDIT LOG TRAFFIC
echo "Generating audit trail traffic..."
CAM_SECURE=$(get_camera_id_by_name "Secure Lab Camera")
CAM_LOBBY=$(get_camera_id_by_name "Lobby Camera")

# Function to simulate view
generate_view_log() {
    local username="$1"
    local camera_id="$2"
    
    # Get a session token for this specific user
    local user_token=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$username\", \"password\": \"Password123!\"}" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

    if [ -n "$user_token" ]; then
        # Accessing HLS stream triggers a "view" event in logs
        # We access for 2 seconds
        timeout 2 curl -sk "${NX_BASE}/hls/${camera_id}.m3u8?auth=${user_token}" > /dev/null || true
        echo "  > Logged traffic: $username viewed $camera_id"
    else
        echo "  ! Failed to login as $username"
    fi
}

# Generate decoy traffic (innocent users viewing Lobby)
for user in "${USERS[@]}"; do
    if [ "$user" != "$SUSPECT" ]; then
        generate_view_log "$user" "$CAM_LOBBY"
    fi
done

# Generate THE LEAK (Suspect viewing Secure Lab)
echo "Generating SUSPECT traffic..."
generate_view_log "$SUSPECT" "$CAM_SECURE"

# Generate more decoy traffic (Admin viewing logs/cameras)
generate_view_log "admin" "$CAM_LOBBY"

# 4. ENVIRONMENT SETUP
# Ensure Firefox is running and on the Web Admin page
# Navigating to System Administration or Dashboard
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system/general"
sleep 5
maximize_firefox

# Clean up any previous report
rm -f /home/ga/leak_report.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Suspect (Internal use only): $SUSPECT"