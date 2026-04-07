#!/bin/bash
set -e
echo "=== Setting up Access Matrix Report Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure server is running and accessible
wait_for_nx_server

# Refresh auth token
NX_TOKEN=$(refresh_nx_token)
echo "Auth token refreshed"

# ============================================================
# Setup Data: Create Users and Layouts
# ============================================================

# 1. Create Users if they don't exist
USERS=("operator1" "operator2" "viewer1")
PASS="Password123!"

for user in "${USERS[@]}"; do
    if ! get_user_by_name "$user" | grep -q "id"; then
        echo "Creating user $user..."
        create_nx_user "$user" "User $user" "$user@example.com" "$PASS" "viewer" > /dev/null
    fi
done

# 2. Get IDs for setup
OP1_ID=$(get_user_by_name "operator1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
OP2_ID=$(get_user_by_name "operator2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
VIEW1_ID=$(get_user_by_name "viewer1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")

# Get Camera IDs
CAM_IDS=$(get_all_cameras | python3 -c "import sys,json; print(' '.join([d['id'] for d in json.load(sys.stdin)]))")
read -r -a CAMS <<< "$CAM_IDS"

if [ ${#CAMS[@]} -lt 2 ]; then
    echo "WARNING: Not enough cameras found (${#CAMS[@]}). Virtual cameras might not be ready."
fi

# 3. Create Specific Layouts (to ensure report has content)

# Layout for Operator1: "Warehouse Ops" (Cam 0 and 1)
if [ -n "$OP1_ID" ] && [ ${#CAMS[@]} -ge 2 ]; then
    LAYOUT_NAME="Warehouse Ops"
    # Check if exists
    if ! get_layout_by_name "$LAYOUT_NAME" | grep -q "id"; then
        ITEMS="[{\"resourceId\": \"${CAMS[0]}\", \"left\":0, \"top\":0, \"right\":0.5, \"bottom\":1}, {\"resourceId\": \"${CAMS[1]}\", \"left\":0.5, \"top\":0, \"right\":1, \"bottom\":1}]"
        
        nx_api_post "/rest/v1/layouts" "{
            \"name\": \"$LAYOUT_NAME\",
            \"parentId\": \"$OP1_ID\",
            \"items\": $ITEMS
        }" > /dev/null
        echo "Created layout '$LAYOUT_NAME' for operator1"
    fi
fi

# Layout for Operator2: "Perimeter Check" (Cam 1)
if [ -n "$OP2_ID" ] && [ ${#CAMS[@]} -ge 2 ]; then
    LAYOUT_NAME="Perimeter Check"
    if ! get_layout_by_name "$LAYOUT_NAME" | grep -q "id"; then
        ITEMS="[{\"resourceId\": \"${CAMS[1]}\", \"left\":0, \"top\":0, \"right\":1, \"bottom\":1}]"
        
        nx_api_post "/rest/v1/layouts" "{
            \"name\": \"$LAYOUT_NAME\",
            \"parentId\": \"$OP2_ID\",
            \"items\": $ITEMS
        }" > /dev/null
        echo "Created layout '$LAYOUT_NAME' for operator2"
    fi
fi

# ============================================================
# Environment Prep
# ============================================================

# Remove any previous report
rm -f /home/ga/access_matrix_report.json

# Open Firefox to API documentation as a hint
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/users"
sleep 5
maximize_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Users and layouts prepared."
echo "Goal: Generate access_matrix_report.json"