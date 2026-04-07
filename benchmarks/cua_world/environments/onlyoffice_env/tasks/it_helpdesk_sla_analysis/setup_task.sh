#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IT Helpdesk SLA Analysis Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/it_helpdesk_sla_analysis_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/q3_incidents.csv"

# Generate the synthetic but highly realistic IT incident dataset
cat > /tmp/create_incident_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

output_path = "/home/ga/Documents/Spreadsheets/q3_incidents.csv"

# SLA Targets in hours
SLA_TARGETS = {
    "P1": 4,
    "P2": 8,
    "P3": 24,
    "P4": 48
}

categories = ["Network", "Hardware", "Software", "Access", "Database"]
assignees = ["Alice.S", "Bob.J", "Charlie.M", "Diana.P", "Evan.R", "Tier1_Queue"]

start_date = datetime(2024, 7, 1, 8, 0, 0)
end_date = datetime(2024, 9, 30, 18, 0, 0)
total_days = (end_date - start_date).days

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Incident_ID", "Created_At", "Resolved_At", "Priority", "Category", "Assignee"])
    
    for i in range(1, 1201):
        inc_id = f"INC-{10000 + i}"
        
        # Random creation time in Q3
        random_days = random.uniform(0, total_days)
        created_at = start_date + timedelta(days=random_days)
        
        # Determine priority (mostly P3/P4, few P1/P2)
        rand_p = random.random()
        if rand_p < 0.05:
            priority = "P1"
        elif rand_p < 0.20:
            priority = "P2"
        elif rand_p < 0.60:
            priority = "P3"
        else:
            priority = "P4"
            
        target_hours = SLA_TARGETS[priority]
        
        # Generate resolution time. Make ~15% breach their SLA
        breach_chance = random.random()
        if breach_chance < 0.15:
            # Breached: 1.01x to 2.5x the target
            duration_hours = target_hours * random.uniform(1.01, 2.5)
        else:
            # Compliant: 0.1x to 0.99x the target
            duration_hours = target_hours * random.uniform(0.1, 0.99)
            
        resolved_at = created_at + timedelta(hours=duration_hours)
        
        cat = random.choice(categories)
        assignee = random.choice(assignees)
        
        writer.writerow([
            inc_id,
            created_at.strftime("%Y-%m-%d %H:%M:%S"),
            resolved_at.strftime("%Y-%m-%d %H:%M:%S"),
            priority,
            cat,
            assignee
        ])

print(f"Generated 1200 incident records at {output_path}")
PYEOF

python3 /tmp/create_incident_data.py
chown ga:ga "$CSV_PATH"

# Take initial screenshot of desktop before starting ONLYOFFICE
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" || true

# Start ONLYOFFICE with the CSV file
echo "Starting ONLYOFFICE with the dataset..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' &"

# Wait for ONLYOFFICE window
wait_for_window "ONLYOFFICE\|Desktop Editors" 30 || true

# Maximize and focus ONLYOFFICE
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

echo "=== Task setup complete ==="