#!/bin/bash
# Setup script for Bulk User Upload task

echo "=== Setting up Bulk User Upload Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Create the CSV file
echo "Creating CSV file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/new_staff_upload.csv << 'CSVEOF'
username,password,firstname,lastname,email,city,country,course1,role1
tnguyen,Onboard2024!,Tanya,Nguyen,tnguyen@healthorg.com,Boston,US,BIO101,student
rkapoor,Onboard2024!,Rajesh,Kapoor,rkapoor@healthorg.com,Boston,US,BIO101,student
lchen,Onboard2024!,Linda,Chen,lchen@healthorg.com,Cambridge,US,BIO101,student
mhernandez,Onboard2024!,Marco,Hernandez,mhernandez@healthorg.com,Boston,US,BIO101,student
sproctor,Onboard2024!,Sarah,Proctor,sproctor@healthorg.com,Somerville,US,BIO101,student
jokwu,Onboard2024!,James,Okwu,jokwu@healthorg.com,Boston,US,,
kfischer,Onboard2024!,Katrin,Fischer,kfischer@healthorg.com,Cambridge,US,,
dpatel,Onboard2024!,Deepa,Patel,dpatel@healthorg.com,Boston,US,,
CSVEOF

chmod 644 /home/ga/Documents/new_staff_upload.csv
chown ga:ga /home/ga/Documents/new_staff_upload.csv

echo "CSV created at /home/ga/Documents/new_staff_upload.csv"

# 2. Ensure BIO101 course exists (required for enrollment)
echo "Checking for BIO101 course..."
COURSE_CHECK=$(get_course_by_shortname "BIO101" 2>/dev/null)

if [ -z "$COURSE_CHECK" ]; then
    echo "BIO101 not found. Creating it..."
    # Create course via PHP CLI to ensure it exists
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        \$data = new stdClass();
        \$data->fullname = 'Introduction to Biology';
        \$data->shortname = 'BIO101';
        \$data->category = 1; 
        try {
            \$course = create_course(\$data);
            echo 'Created BIO101 (id: ' . \$course->id . ')';
        } catch (Exception \$e) {
            echo 'Error: ' . \$e->getMessage();
            exit(1);
        }
    "
else
    echo "BIO101 exists."
fi

# 3. Clean up any pre-existing users from the list (idempotency)
echo "Ensuring target users do not already exist..."
TARGET_USERS="'tnguyen','rkapoor','lchen','mhernandez','sproctor','jokwu','kfischer','dpatel'"
moodle_query "DELETE FROM mdl_user WHERE username IN ($TARGET_USERS)"
# Also clean associated enrollments if any remnants exist (cascading delete usually handles this, but safe to be sure)
echo "Cleaned up target users."

# 4. Record initial state
INITIAL_USER_COUNT=$(get_user_count 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
date +%s > /tmp/task_start_time

# 5. Start Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|Moodle" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="