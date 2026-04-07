#!/bin/bash
# Setup script for Reactivate Patient Record task

echo "=== Setting up Reactivate Patient Task ==="

# 1. Ensure NOSH database container is running
if ! docker ps | grep -q nosh-db; then
    echo "Error: nosh-db container not running"
    exit 1
fi

# 2. Prepare the specific patient data (Maria Garcia)
# We need to ensure she exists and is set to INACTIVE (0)
echo "Preparing patient record..."

# Create patient if not exists (using INSERT IGNORE to handle existing)
# Note: pid is auto-increment, letting DB handle it.
# We explicitly set active=0.
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (firstname, lastname, DOB, sex, active) 
SELECT * FROM (SELECT 'Maria', 'Garcia', '1980-03-25', 'Female', 0) AS tmp
WHERE NOT EXISTS (
    SELECT pid FROM demographics WHERE firstname='Maria' AND lastname='Garcia' AND DOB='1980-03-25'
) LIMIT 1;
" 2>/dev/null

# Force update to ensure she is inactive (in case she existed but was active)
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
UPDATE demographics SET active=0 WHERE firstname='Maria' AND lastname='Garcia' AND DOB='1980-03-25';
" 2>/dev/null

# 3. Record initial state for verification
# We record the PID and the count of records for this name (should be 1)
INITIAL_STATE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
SELECT pid, active FROM demographics WHERE firstname='Maria' AND lastname='Garcia' AND DOB='1980-03-25';
")

PID=$(echo "$INITIAL_STATE" | awk '{print $1}')
ACTIVE=$(echo "$INITIAL_STATE" | awk '{print $2}')
COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM demographics WHERE firstname='Maria' AND lastname='Garcia';")

echo "Target PID: $PID"
echo "Initial Active Status: $ACTIVE"
echo "Initial Record Count: $COUNT"

# Save to tmp file for export script
cat > /tmp/reactivate_initial_state.json << EOF
{
    "target_pid": "$PID",
    "initial_active": "$ACTIVE",
    "initial_count": $COUNT,
    "setup_timestamp": $(date +%s)
}
EOF

# 4. Set up Firefox at Login Page
echo "Setting up Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
find /home/ga/.mozilla -name "*.lock" -delete 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="