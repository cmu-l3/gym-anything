#!/bin/bash
echo "=== Setting up O*NET Occupational Requisition Alignment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Sentrifugo HTTP readiness
wait_for_http "$SENTRIFUGO_URL" 60

echo "Cleaning up any prior run artifacts..."
# Deactivate titles if they exist to ensure a clean slate
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
    UPDATE main_jobtitles SET isactive=0 
    WHERE jobtitlename IN ('Financial Manager', 'Training and Development Manager');
" 2>/dev/null || true

# Purge any existing requisitions with those titles
REQ_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='sentrifugo' AND table_name LIKE '%requisition%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -n "$REQ_TABLE" ]; then
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
        DELETE FROM $REQ_TABLE 
        WHERE jobtitle_id IN (
            SELECT id FROM main_jobtitles 
            WHERE jobtitlename IN ('Financial Manager', 'Training and Development Manager')
        );
    " 2>/dev/null || true
fi

# Create desktop directory
mkdir -p /home/ga/Desktop

# Generate O*NET Financial Manager file
cat > /home/ga/Desktop/ONET_Financial_Manager_Tasks.txt << 'EOF'
O*NET Code: 11-3031.00
Occupation: Financial Managers

Official Task Statement:
Direct and coordinate financial activities of workers in a branch, office, or department.
EOF

# Generate O*NET Training Manager file
cat > /home/ga/Desktop/ONET_Training_Manager_Tasks.txt << 'EOF'
O*NET Code: 11-3131.00
Occupation: Training and Development Managers

Official Task Statement:
Plan, direct, or coordinate the training and development activities and staff of an organization.
EOF

# Fix permissions
chown -R ga:ga /home/ga/Desktop/ONET_*.txt

# Launch browser and ensure Sentrifugo is logged in
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"

# Wait for page load
sleep 5

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="