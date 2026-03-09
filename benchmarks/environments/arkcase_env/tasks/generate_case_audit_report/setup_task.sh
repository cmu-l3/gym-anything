#!/bin/bash
# pre_task: Set up the generate_case_audit_report task
# 1. Ensures ArkCase is running
# 2. Creates 6 specific complaint cases via API
# 3. Logs in and sets up browser

echo "=== Setting up generate_case_audit_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

ensure_portforward
wait_for_arkcase

echo "Preparing dataset..."

# Define cases to create (Title|Details|Priority|Status)
# Using Array of strings for simplicity
CASES=(
    "Noise Complaint - Industrial District|Loud machinery operating after 10PM violation|High|ACTIVE"
    "Improper Waste Disposal at 45 Oak Lane|Chemical barrels observed in residential dumpsters|High|ACTIVE"
    "Sidewalk Obstruction on Main Street|Restaurant tables blocking pedestrian path|Medium|ACTIVE"
    "Delayed Building Permit Response|Applicant claims 30 day delay on permit #4492|Medium|CLOSED"
    "Unauthorized Construction at 78 Pine Road|Garage extension without visible permit|Low|ACTIVE"
    "Street Light Outage Complaint|Pole #552 flickering continuously|Low|CLOSED"
)

# Function to create a case
create_case() {
    local title="$1"
    local details="$2"
    local priority="$3"
    local status="$4"
    
    echo "Creating case: $title ($status)"
    
    # Construct JSON payload
    # Note: Using simple string concatenation for payload to avoid jq dependency issues inside bare helper
    local payload="{\"caseType\":\"GENERAL\",\"complaintTitle\":\"$title\",\"details\":\"$details\",\"priority\":\"$priority\",\"status\":\"$status\"}"
    
    arkcase_api POST "plugin/complaint" "$payload" > /dev/null 2>&1
}

# Create all cases
for case_info in "${CASES[@]}"; do
    IFS="|" read -r title details priority status <<< "$case_info"
    create_case "$title" "$details" "$priority" "$status"
    sleep 1
done

echo "Dataset preparation complete."

# Browser Setup
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox on ArkCase login page
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
URL="https://localhost:9443/arkcase/login"

if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$URL' &>/dev/null &" &
fi
sleep 15

focus_firefox
maximize_firefox
sleep 2

# Log in to ArkCase (Admin)
# Login form coordinates in 1920x1080
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 12

# Navigate to Dashboard (default post-login, but ensuring)
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/home.html'
DISPLAY=:1 xdotool key Return
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="