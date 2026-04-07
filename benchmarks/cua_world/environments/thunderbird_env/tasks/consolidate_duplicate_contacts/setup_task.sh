#!/bin/bash
echo "=== Setting up Consolidate Duplicate Contacts task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed before modifying databases
pkill -f thunderbird 2>/dev/null || true
sleep 2

# Find the active Thunderbird profile
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -type d -name "*default*" | head -n 1)
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.thunderbird/default-release"
    mkdir -p "$PROFILE_DIR"
fi
echo "Using profile directory: $PROFILE_DIR"

# Pre-populate the Address Book with SQLite via a Python script
cat << 'EOF' > /tmp/seed_abook.py
import sqlite3
import uuid
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Ensure properties table exists (Thunderbird standard)
c.execute("CREATE TABLE IF NOT EXISTS properties (card TEXT, name TEXT, value TEXT)")

def add_contact(props):
    card_id = str(uuid.uuid4())
    # Newer Thunderbird versions sometimes have a cards table; safely try to insert
    try:
        c.execute("CREATE TABLE IF NOT EXISTS cards (uid TEXT PRIMARY KEY)")
        c.execute("INSERT INTO cards (uid) VALUES (?)", (card_id,))
    except Exception:
        pass

    for k, v in props.items():
        c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, k, v))

# Insert the fragmented target entries (to be consolidated)
add_contact({
    "FirstName": "Bob",
    "LastName": "Chen",
    "DisplayName": "Bob Chen",
    "PrimaryEmail": "bob.chen@oldcompany.com",
    "WorkPhone": "555-0198"
})

add_contact({
    "FirstName": "Robert",
    "LastName": "Chen",
    "DisplayName": "Robert Chen (Old)",
    "PrimaryEmail": "robert.chen@apexfinancial.com"
})

add_contact({
    "FirstName": "Robert",
    "LastName": "Chen",
    "DisplayName": "Robert Chen (Personal)",
    "PrimaryEmail": "rchen99@gmail.com"
})

# Insert noise contacts to simulate a realistic address book
for i in range(1, 25):
    add_contact({
        "FirstName": f"John{i}",
        "LastName": f"Doe{i}",
        "DisplayName": f"John Doe {i}",
        "PrimaryEmail": f"john.doe{i}@example.com",
        "Company": "Random Corp"
    })

conn.commit()
conn.close()
EOF

python3 /tmp/seed_abook.py "$PROFILE_DIR/abook.sqlite"
chown -R ga:ga "$PROFILE_DIR"

# Launch Thunderbird in the background
su - ga -c "DISPLAY=:1 thunderbird &"
sleep 5

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Thunderbird\|Thunderbird"; then
        echo "Thunderbird window detected."
        break
    fi
    sleep 1
done

# Maximize and focus Thunderbird
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Thunderbird" 2>/dev/null || true

# Allow UI to stabilize and take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="