#!/bin/bash
echo "=== Setting up update_provider_directory task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
INBOX_FILE="${PROFILE_DIR}/Mail/Local Folders/Inbox"

# Ensure Thunderbird is closed before modifying DB to prevent locking
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

# Create Python script to populate Address Book with synthetic realistic data
cat > /tmp/setup_db.py << 'EOF'
import sqlite3
import os
import uuid

profile_dir = "/home/ga/.thunderbird/default-release"
db_path = os.path.join(profile_dir, "abook.sqlite")
os.makedirs(profile_dir, exist_ok=True)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE IF NOT EXISTS cards (uid TEXT PRIMARY KEY, local_key INTEGER)")
c.execute("CREATE TABLE IF NOT EXISTS properties (card TEXT, name TEXT, value TEXT)")

c.execute("DELETE FROM cards")
c.execute("DELETE FROM properties")

def add_card(fname, lname, email, phone, title):
    uid = str(uuid.uuid4())
    c.execute("INSERT INTO cards (uid) VALUES (?)", (uid,))
    props = [
        (uid, "FirstName", fname),
        (uid, "LastName", lname),
        (uid, "DisplayName", f"Dr. {fname} {lname}"),
        (uid, "PrimaryEmail", email),
        (uid, "WorkPhone", phone),
        (uid, "JobTitle", title),
        (uid, "RecordKey", uid)
    ]
    c.executemany("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", props)

# Add Robert Vance (the retiring doctor that must be deleted)
add_card("Robert", "Vance", "r.vance@synthea.example.com", "555-123-4567", "Neurologist")

# Add some other providers to populate the book
add_card("Alice", "Smith", "a.smith@synthea.example.com", "555-987-6543", "Cardiologist")
add_card("John", "Doe", "j.doe@synthea.example.com", "555-456-7890", "Surgeon")
add_card("Mary", "Jane", "m.jane@synthea.example.com", "555-321-0987", "Pediatrician")
add_card("James", "Wilson", "j.wilson@synthea.example.com", "555-555-5555", "Oncologist")

# Fill it up to > 50 records to ensure scrolling and search functionality is needed
for i in range(1, 46):
    add_card(f"Doc{i}", f"Test{i}", f"doc{i}@synthea.example.com", f"555-000-{1000+i}", "General")

conn.commit()
conn.close()
EOF

# Execute the DB setup
python3 /tmp/setup_db.py

# Inject the incoming email into the local Inbox
DATE_STR=$(date -R)
mkdir -p "${PROFILE_DIR}/Mail/Local Folders"

cat << EOF >> "$INBOX_FILE"

From hr@synthea.example.com $(date)
From: HR Department <hr@synthea.example.com>
To: Clinic Staff <staff@clinic.example.com>
Subject: Provider Roster Update: November
Date: $DATE_STR
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Dear Staff,

Please note the following changes to our provider roster for this month. Update your local address books accordingly.

RETIREMENTS:
- Dr. Robert Vance is retiring effective immediately. Please remove his contact from the directory.

NEW HIRES:
Please welcome our new provider and add her to your contacts:
First Name: Sarah
Last Name: Jenkins
Display Name: Dr. Sarah Jenkins
Email: s.jenkins@synthea.example.com
Work Phone: 555-839-2011
Title: Neurologist

Thank you,
HR Department

EOF

# Force Thunderbird to rebuild the index when it opens
rm -f "${PROFILE_DIR}/Mail/Local Folders/Inbox.msf"
chown -R ga:ga "$PROFILE_DIR"

# Launch Thunderbird as the ga user
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
sleep 5

# Wait for the window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take an initial screenshot proving the task start state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="