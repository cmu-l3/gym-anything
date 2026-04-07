#!/bin/bash
echo "=== Setting up create_accommodation_exam task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png /tmp/initial_exam_count.txt 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

echo "=== Seeding database with required entities ==="

# 1. Seed Configurations
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
INSERT INTO configuration_node (name, type, description) VALUES ('Standard_Lockdown_Profile', 'EXAM_CONFIG', 'Standard high security exam profile');
" 2>/dev/null || true

docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
INSERT INTO configuration_node (name, type, description) VALUES ('Accessibility_Profile_v2', 'EXAM_CONFIG', 'Profile permitting assistive technology');
" 2>/dev/null || true

STD_CONF_ID=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM configuration_node WHERE name='Standard_Lockdown_Profile' LIMIT 1" 2>/dev/null)

# 2. Inspect exam schema to be safe
START_COL=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SHOW COLUMNS FROM exam LIKE 'start_%'" | awk '{print $1}' | head -1)
END_COL=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SHOW COLUMNS FROM exam LIKE 'end_%'" | awk '{print $1}' | head -1)
CONF_COL=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SHOW COLUMNS FROM exam LIKE '%configuration_id%'" | awk '{print $1}' | head -1)

START_COL=${START_COL:-start_time}
END_COL=${END_COL:-end_time}
CONF_COL=${CONF_COL:-exam_configuration_id}

# 3. Create Original Exam (Randomize start time to ensure agent checks it)
# We pick a time between 10 and 20 days in the future, at 14:00.
OFFSET_DAYS=$((10 + RANDOM % 10))
START_VAL=$(date -d "+$OFFSET_DAYS days 14:00:00" +"%Y-%m-%d %H:%M:%S")
END_VAL=$(date -d "+$OFFSET_DAYS days 16:30:00" +"%Y-%m-%d %H:%M:%S")

docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
INSERT INTO exam (name, description, $START_COL, $END_COL, $CONF_COL) 
VALUES ('Introduction to Psychology', 'Standard Final Examination', '$START_VAL', '$END_VAL', ${STD_CONF_ID:-1});
" 2>/dev/null || true

echo "Seeded exam 'Introduction to Psychology' at $START_VAL to $END_VAL."

# Record baseline
EXAM_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM exam" 2>/dev/null)
echo "${EXAM_COUNT:-0}" > /tmp/initial_exam_count.txt

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="