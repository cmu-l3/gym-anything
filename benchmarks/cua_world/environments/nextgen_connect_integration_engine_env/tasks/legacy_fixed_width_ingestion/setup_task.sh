#!/bin/bash
set -e
echo "=== Setting up Legacy Fixed-Width Ingestion Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure NextGen Connect is running
if ! docker ps | grep -q "nextgen-connect"; then
    echo "Starting NextGen Connect..."
    # Rely on environment's setup script usually, but ensure it's up here
    /workspace/scripts/setup_nextgen_connect.sh
fi

# Wait for API to be ready
wait_for_api 60

# Clean up container directories (Inbox/Outbox)
echo "Cleaning container directories..."
docker exec nextgen-connect mkdir -p /var/spool/mirth/inbox
docker exec nextgen-connect mkdir -p /var/spool/mirth/outbox
docker exec nextgen-connect sh -c 'rm -f /var/spool/mirth/inbox/* /var/spool/mirth/outbox/*'
docker exec nextgen-connect chmod 777 /var/spool/mirth/inbox /var/spool/mirth/outbox

# Generate Synthetic Fixed-Width Data
DATA_FILE="/home/ga/Documents/legacy_census.dat"
mkdir -p "$(dirname "$DATA_FILE")"

echo "Generating synthetic legacy data at $DATA_FILE..."
python3 -c '
import random

def pad(text, length):
    return text.ljust(length)[:length]

records = [
    ("1000459821", "Smith", "John", "19800101", "M"),
    ("1000459822", "Doe", "Jane", "19850515", "F"),
    ("1000459823", "O''Connor", "Patrick", "19791225", "M"),
    ("1000459824", "Van Der Hoven", "Maria", "19900704", "F"),
    ("1000459825", "Lee", "Christopher", "19880910", "M")
]

with open("'"$DATA_FILE"'", "w") as f:
    for mrn, last, first, dob, gender in records:
        line = f"{pad(mrn, 10)}{pad(last, 20)}{pad(first, 20)}{pad(dob, 8)}{pad(gender, 1)}\n"
        f.write(line)
'

# Set permissions for the agent
chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"

# Save ground truth for verification (hidden in tmp)
cp "$DATA_FILE" /tmp/legacy_census_truth.dat

# Open Firefox to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
fi

# Maximize Firefox
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open a terminal for the agent to perform docker cp operations
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "=== Legacy Data Ingestion Task ==="
echo "Data File: /home/ga/Documents/legacy_census.dat"
echo "Container Name: nextgen-connect"
echo "Container Inbox: /var/spool/mirth/inbox"
echo "Container Outbox: /var/spool/mirth/outbox"
echo ""
echo "Use docker cp to move files."
echo ""
exec bash
' 2>/dev/null &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="