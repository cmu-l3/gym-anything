#!/bin/bash
echo "=== Setting up import_panama_papers_csv task ==="

source /workspace/scripts/task_utils.sh

# Ensure Visallo is ready
if ! ensure_visallo_ready 30; then
    echo "CRITICAL ERROR: Visallo is not accessible."
    exit 1
fi

date +%s > /tmp/task_start_time

# Ensure Panama Papers CSV is in user's Documents
mkdir -p /home/ga/Documents
cp /workspace/data/panama_papers_entities.csv /home/ga/Documents/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents
echo "CSV file: $(wc -l /home/ga/Documents/panama_papers_entities.csv 2>/dev/null) lines"

# Restart Firefox, login, and navigate to dashboard
restart_firefox "$VISALLO_URL/"
sleep 2
visallo_login "analyst"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see Visallo dashboard. CSV file is at /home/ga/Documents/panama_papers_entities.csv"
