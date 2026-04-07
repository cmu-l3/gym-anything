#!/bin/bash
set -e
echo "=== Setting up import_schedule_from_csv task ==="

# 1. Create the CSV file with realistic event planning data
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Projects

CSV_FILE="/home/ga/Documents/festival_plan.csv"

# Note: Using simple "X days" format which ProjectLibre parses well
cat > "$CSV_FILE" << 'EOF'
Name,Duration,Start
Site Survey,1 day,2026-06-01
Permit Application,5 days,2026-06-02
Vendor Contracts,10 days,2026-06-02
Stage Construction,3 days,2026-06-15
Sound Check,1 day,2026-06-18
Festival Opening,0 days,2026-06-20
EOF

chown ga:ga "$CSV_FILE"
echo "Created CSV file at $CSV_FILE"

# 2. Clean up previous results
rm -f /home/ga/Projects/festival_project.xml
rm -f /tmp/task_result.json

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch ProjectLibre (empty state)
# We launch it so the agent doesn't have to find the icon, but they must use File > Open
if ! pgrep -f "projectlibre" > /dev/null; then
    echo "Starting ProjectLibre..."
    su - ga -c "DISPLAY=:1 setsid projectlibre > /tmp/projectlibre.log 2>&1 &"
    
    # Wait for window
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
            echo "ProjectLibre window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="