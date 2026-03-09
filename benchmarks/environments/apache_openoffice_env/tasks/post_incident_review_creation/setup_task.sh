#!/bin/bash
# Setup script for Post-Incident Review Creation task

echo "=== Setting up PIR Creation Task ==="
source /workspace/scripts/task_utils.sh

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/INC-4092_PIR.odt 2>/dev/null || true
rm -f /home/ga/Documents/incident_ticket_4092.json 2>/dev/null || true

# 3. Create the Incident Data JSON file
cat > /home/ga/Documents/incident_ticket_4092.json << 'EOF'
{
  "incident_id": "INC-4092",
  "date": "2024-03-15",
  "severity": "SEV-1",
  "duration": "45 minutes",
  "impact": "100% of checkout requests failed during Flash Sale",
  "timeline": [
    {"time": "14:00 UTC", "event": "Alert fired: High error rate on POST /api/checkout"},
    {"time": "14:05 UTC", "event": "War room assembled. On-call engineer confirmed database timeout."},
    {"time": "14:15 UTC", "event": "DBA identified locking contention on 'inventory_items' table."},
    {"time": "14:30 UTC", "event": "Hotfix deployed to implement exponential backoff."},
    {"time": "14:45 UTC", "event": "Error rate returned to normal. Incident resolved."}
  ],
  "root_cause_details": {
    "summary": "A deadlock occurred in the PostgreSQL database due to concurrent updates.",
    "technical_finding": "Multiple transactions attempted to update the same SKU row in 'inventory_items' simultaneously, resulting in SQLSTATE 40P01 errors."
  },
  "corrective_actions": [
    {"action": "Implement optimistic locking for inventory updates", "owner": "Backend Team", "due_date": "2024-03-20"},
    {"action": "Add composite index to inventory table", "owner": "DBA Team", "due_date": "2024-03-21"},
    {"action": "Update incident response playbook for DB deadlocks", "owner": "SRE Team", "due_date": "2024-03-22"}
  ],
  "chat_log_excerpt": [
    "[14:02] alice: Is the site down?",
    "[14:03] bob: I'm seeing 500s on checkout.",
    "[14:10] cto: We are losing $50k/minute. Status?",
    "[14:12] dba: It's a deadlock. The query on inventory_items is stuck."
  ]
}
EOF
chown ga:ga /home/ga/Documents/incident_ticket_4092.json
chmod 644 /home/ga/Documents/incident_ticket_4092.json

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Apache OpenOffice Writer
echo "Starting OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Writer"; then
            echo "Writer window found"
            break
        fi
        sleep 1
    done
fi

# 6. Maximize and focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="