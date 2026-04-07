#!/bin/bash
echo "=== Setting up Export Custom Address Book Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
# Remove any existing CSV files to prevent gaming
rm -f /home/ga/Documents/*.csv 2>/dev/null

PROFILE_DIR="/home/ga/.thunderbird/default-release"
sudo -u ga mkdir -p "$PROFILE_DIR"

# Ensure Thunderbird is closed before modifying SQLite
if pgrep -x "thunderbird" > /dev/null 2>&1; then
    pkill -x "thunderbird"
    sleep 2
fi

# Inject realistic background CRM data into the Personal Address Book
# This forces the agent to properly isolate the export.
echo "Injecting background CRM contacts..."
cat > /tmp/inject_contacts.py << 'EOF'
import sqlite3
import uuid
import os

db_path = "/home/ga/.thunderbird/default-release/abook.sqlite"
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE IF NOT EXISTS properties (card TEXT, name TEXT, value TEXT)")

# Realistic sample CRM data
contacts = [
    {"FirstName": "Eleanor", "LastName": "Vargas", "DisplayName": "Eleanor Vargas", "PrimaryEmail": "e.vargas@global-logistics.net", "Company": "Global Logistics"},
    {"FirstName": "David", "LastName": "Chen", "DisplayName": "David Chen", "PrimaryEmail": "david.chen@horizon-tech.io", "Company": "Horizon Technologies"},
    {"FirstName": "Amina", "LastName": "Rossi", "DisplayName": "Amina Rossi", "PrimaryEmail": "arossi@mediterranean-shipping.com", "Company": "Mediterranean Shipping"},
    {"FirstName": "James", "LastName": "O'Connor", "DisplayName": "James O'Connor", "PrimaryEmail": "joconnor@emerald-financial.ie", "Company": "Emerald Financial"},
    {"FirstName": "Yuki", "LastName": "Tanaka", "DisplayName": "Yuki Tanaka", "PrimaryEmail": "y.tanaka@tokyo-robotics.jp", "Company": "Tokyo Robotics"},
    {"FirstName": "Chloe", "LastName": "Dubois", "DisplayName": "Chloe Dubois", "PrimaryEmail": "c.dubois@lumiere-design.fr", "Company": "Lumiere Design"},
    {"FirstName": "Mateo", "LastName": "Silva", "DisplayName": "Mateo Silva", "PrimaryEmail": "msilva@agricola-sur.com", "Company": "Agricola Sur"},
    {"FirstName": "Zara", "LastName": "Ali", "DisplayName": "Zara Ali", "PrimaryEmail": "zara.ali@quantum-compute.co.uk", "Company": "Quantum Compute"},
    {"FirstName": "Lars", "LastName": "Hansen", "DisplayName": "Lars Hansen", "PrimaryEmail": "lhansen@nordic-energy.no", "Company": "Nordic Energy"},
    {"FirstName": "Priya", "LastName": "Patel", "DisplayName": "Priya Patel", "PrimaryEmail": "ppatel@mumbai-textiles.in", "Company": "Mumbai Textiles"}
]

for contact in contacts:
    card_id = str(uuid.uuid4())
    for k, v in contact.items():
        c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, k, v))

conn.commit()
conn.close()
EOF

python3 /tmp/inject_contacts.py
chown -R ga:ga "$PROFILE_DIR"

# Count initial address books (abook*.sqlite files)
INITIAL_ABOOKS=$(ls -1 "$PROFILE_DIR"/abook*.sqlite 2>/dev/null | wc -l)
echo "$INITIAL_ABOOKS" > /tmp/initial_abook_count.txt

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="