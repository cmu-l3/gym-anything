#!/bin/bash
# Setup script for multi_tenant_team_onboarding task

echo "=== Setting up multi_tenant_team_onboarding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Ensure staging namespace exists with its workloads (should be created by env setup, but ensure it's untethered)
docker exec rancher kubectl create namespace staging 2>/dev/null || true
docker exec rancher kubectl annotate namespace staging field.cattle.io/projectId- 2>/dev/null || true

# Get an admin token for API operations
TOKEN=$(get_rancher_token)

if [ -n "$TOKEN" ]; then
    echo "Cleaning up any existing users/projects from previous runs..."
    
    # Clean users
    for user in alice-chen bob-kumar carol-santos dave-oconnor; do
        USER_ID=$(curl -sk "$RANCHER_URL/v3/users?username=$user" -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id // empty')
        if [ -n "$USER_ID" ]; then
            curl -sk -X DELETE "$RANCHER_URL/v3/users/$USER_ID" -H "Authorization: Bearer $TOKEN" >/dev/null
        fi
    done

    # Clean projects
    for proj in backend-services frontend-services; do
        PROJ_ID=$(curl -sk "$RANCHER_URL/v3/projects?clusterId=local&name=$proj" -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id // empty')
        if [ -n "$PROJ_ID" ]; then
            curl -sk -X DELETE "$RANCHER_URL/v3/projects/$PROJ_ID" -H "Authorization: Bearer $TOKEN" >/dev/null
        fi
    done
fi

# Clean namespace
docker exec rancher kubectl delete namespace frontend-staging --wait=false 2>/dev/null || true

# Ensure Firefox is running and focused on the Rancher dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard &"
    sleep 5
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="