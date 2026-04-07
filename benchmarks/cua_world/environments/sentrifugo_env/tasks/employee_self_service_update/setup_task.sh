#!/bin/bash
echo "=== Setting up employee_self_service_update task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Wait for Sentrifugo DB & web server to be ready
wait_for_http "http://localhost" 60

# 1. Prepare David Kim's account (EMP005 usually, but we find him by name)
UID_DAVID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='David' AND lastname='Kim' LIMIT 1;" | tr -d '[:space:]')

if [ -z "$UID_DAVID" ]; then
    echo "Error: David Kim not found in database. Using ID 5 as fallback."
    UID_DAVID=5
fi
echo "Found David Kim at User ID: $UID_DAVID"

# Reset David Kim's password to 'password123' (Sentrifugo stores plain MD5 hashes)
# Set his email so the user can easily log in
sentrifugo_db_root_query "UPDATE main_users SET emppassword=MD5('password123'), emailaddress='david.kim@sentrifugo.local' WHERE id=${UID_DAVID};"

# Clean up existing personal data for David Kim to ensure a blank slate
sentrifugo_db_root_query "DELETE FROM main_useraddresses WHERE user_id=${UID_DAVID};"
sentrifugo_db_root_query "DELETE FROM main_employeeemergencycontacts WHERE user_id=${UID_DAVID};"
sentrifugo_db_root_query "DELETE FROM main_employeedependents WHERE user_id=${UID_DAVID};"
sentrifugo_db_root_query "DELETE FROM main_userprofileupdates WHERE user_id=${UID_DAVID};"

# 2. Provide instructions file
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/urgent_profile_update.txt << 'EOF'
From: David Kim <david.kim@sentrifugo.local>
To: HR Support
Subject: URGENT: Profile Updates for Insurance Enrollment

Hi HR,

I am currently traveling with limited internet and cannot access the portal. My health insurance enrollment is due today. Could you please log into the Sentrifugo Self-Service portal on my behalf and update my profile?

Credentials:
URL: http://localhost
Username/Email: david.kim@sentrifugo.local
Password: password123

1. Update my Address:
Address Line 1: 8472 Redwood Horizon Blvd
Address Line 2: Apt 4B
City: Seattle
State: Washington
Zip: 98101
Country: United States

2. Add Emergency Contact:
Name: Eleanor Vance-Kim
Relationship: Spouse
Phone: 206-555-8472

3. Add Dependent:
Name: Eleanor Vance-Kim
Relationship: Spouse

4. Profile Picture:
I have attached my new photo. Please upload it to my profile.
(Saved at ~/Desktop/david_profile_pic.jpg)

Thank you so much!
David
EOF

# 3. Download a real, creative-commons profile picture
wget -qO /home/ga/Desktop/david_profile_pic.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/Pierre-Person.jpg/512px-Pierre-Person.jpg"

chown ga:ga /home/ga/Desktop/urgent_profile_update.txt /home/ga/Desktop/david_profile_pic.jpg

# 4. Start Firefox at the login page
stop_firefox
clear_firefox_profile_locks

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox 'http://localhost' > /tmp/firefox_task.log 2>&1 &"

# Wait for browser window and focus it
sleep 5
wait_for_window "firefox" 30

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_active_window
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="