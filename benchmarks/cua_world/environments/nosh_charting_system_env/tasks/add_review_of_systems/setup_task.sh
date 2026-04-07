#!/bin/bash
set -e
echo "=== Setting up task: Add Review of Systems ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Create patient Margaret Thompson (pid=999) if not exists
# ============================================================
echo "Creating patient Margaret Thompson..."
# Clean up potential previous runs
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM ros WHERE eid=999;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM encounters WHERE eid=999;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM demographics WHERE pid=999;" 2>/dev/null || true

# Insert Patient
echo "INSERT IGNORE INTO \`demographics\` (\`pid\`, \`firstname\`, \`lastname\`, \`DOB\`, \`sex\`, \`active\`, \`address\`, \`city\`, \`state\`, \`zip\`, \`phone_home\`) VALUES (999, 'Margaret', 'Thompson', '1958-04-22', 'Female', 1, '45 Birchwood Lane', 'Springfield', 'MA', '01103', '413-555-8821');" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Create demographics_relate entry (required for patient to appear in lists)
echo "INSERT IGNORE INTO \`demographics_relate\` (\`pid\`, \`id\`, \`practice_id\`) VALUES (999, 2, 1);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# ============================================================
# Create an encounter for today
# ============================================================
TODAY=$(date +%Y-%m-%d)
echo "Creating encounter for today ($TODAY)..."

# Note: In NOSH, encounters are linked to patients via pid. 
# eid is usually auto-increment, but we force 999 for verifiability if possible, 
# or we let it auto-increment and find it later. 
# For stability, we force eid=999.
echo "INSERT IGNORE INTO \`encounters\` (\`eid\`, \`pid\`, \`encounter_provider\`, \`encounter_DOS\`, \`encounter_signed\`, \`encounter_cc\`, \`practice_id\`, \`encounter_role\`, \`encounter_template\`, \`encounter_age\`) VALUES (999, 999, 'Dr. James Carter', '${TODAY} 10:00:00', 'No', 'Fatigue and joint pain evaluation', 1, 'provider', 'standardmedical', '66 years old');" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# ============================================================
# Record initial ROS count for anti-gaming
# ============================================================
INITIAL_ROS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM ros WHERE eid=999" 2>/dev/null || echo "0")
echo "$INITIAL_ROS" > /tmp/initial_ros_count.txt
echo "Initial ROS count for encounter 999: $INITIAL_ROS"

# ============================================================
# Open Firefox to NOSH login page
# ============================================================
echo "Opening Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost/login' > /dev/null 2>&1 &"
sleep 8

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|nosh|login|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="