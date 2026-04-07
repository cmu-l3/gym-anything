#!/bin/bash
echo "=== Setting up proxy_leave_entry_and_approval task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Sentrifugo to be ready
for i in {1..60}; do
    if curl -s http://localhost/ > /dev/null 2>&1; then
        echo "Sentrifugo HTTP interface ready"
        break
    fi
    sleep 2
done

# Clean up any existing leave requests for 2026 to ensure a clean state
# Try multiple potential table names to be safe across versions
for table in main_leaverequest main_leaverequests main_employeeleaverequests; do
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e \
        "DELETE FROM $table WHERE fromdate LIKE '2026-%' OR startdate LIKE '2026-%';" 2>/dev/null || true
done
echo "Cleaned prior leave requests for 2026."

# Ensure target users have active accounts
for EMPID in EMP004 EMP007 EMP012 EMP019; do
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e \
        "UPDATE main_users SET isactive=1 WHERE employeeId='$EMPID';" 2>/dev/null || true
done

# Create the offline leave requests manifest on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/field_leave_requests.txt << 'EOF'
FIELD LEAVE REQUESTS - OFFLINE LOG
-----------------------------------
Source: Community Outreach Field Team
Period: Q1/Q2 2026

Please enter and approve the following leave requests in the HRMS on behalf of these employees.

Employee: Emily Williams (EMP004)
Leave Type: Sick Leave
Dates: 2026-04-02 to 2026-04-03

Employee: Robert Patel (EMP007)
Leave Type: Annual Leave
Dates: 2026-03-25 to 2026-03-26

Employee: Jennifer Martinez (EMP012)
Leave Type: Sick Leave
Dates: 2026-04-06 to 2026-04-06

Employee: Tyler Moore (EMP019)
Leave Type: Annual Leave
Dates: 2026-03-30 to 2026-04-01
EOF
chown ga:ga /home/ga/Desktop/field_leave_requests.txt

# Start Firefox and navigate to the Sentrifugo dashboard
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox 'http://localhost' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window to appear and maximize it
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take screenshot of initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="