#!/bin/bash
set -e
echo "=== Setting up Address Book Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed before touching its database
echo "Closing any running Thunderbird instances..."
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

TB_PROFILE="/home/ga/.thunderbird/default-release"
mkdir -p "$TB_PROFILE"

# Inject real Enron contact data into the Address Book
echo "Injecting Enron employee directory into Address Book..."
python3 - << 'EOF'
import sqlite3
import uuid
import os

db_path = '/home/ga/.thunderbird/default-release/abook.sqlite'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create Thunderbird minimal schema
c.execute("CREATE TABLE IF NOT EXISTS properties (card TEXT, name TEXT, value TEXT)")
c.execute("CREATE TABLE IF NOT EXISTS cards (uid TEXT PRIMARY KEY, local_key INTEGER)")

contacts = [
    # Legal Department (Targets)
    ("Sally", "Beck", "Legal", "sally.beck@enron.com"),
    ("Mark", "Taylor", "Legal", "mark.taylor@enron.com"),
    ("Sara", "Shackleton", "Legal", "sara.shackleton@enron.com"),
    ("Carol", "St. Clair", "Legal", "carol.st.clair@enron.com"),
    ("Tana", "Jones", "Legal", "tana.jones@enron.com"),
    ("Richard", "Sanders", "Legal", "richard.sanders@enron.com"),
    # Other Departments (Non-targets)
    ("Kenneth", "Lay", "Executive", "kenneth.lay@enron.com"),
    ("Jeffrey", "Skilling", "Executive", "jeffrey.skilling@enron.com"),
    ("Andrew", "Fastow", "Finance", "andrew.fastow@enron.com"),
    ("Greg", "Whalley", "Trading", "greg.whalley@enron.com"),
    ("John", "Lavorato", "Trading", "john.lavorato@enron.com"),
    ("Vince", "Kaminski", "Research", "vince.kaminski@enron.com"),
    ("Louise", "Kitchen", "Trading", "louise.kitchen@enron.com"),
    ("Rick", "Buy", "Risk Management", "rick.buy@enron.com"),
    ("Steven", "Kean", "Public Relations", "steven.kean@enron.com"),
    ("Richard", "Causey", "Accounting", "richard.causey@enron.com")
]

for idx, (first, last, dept, email) in enumerate(contacts):
    card_id = str(uuid.uuid4())
    display_name = f"{first} {last}"
    c.execute("INSERT INTO cards (uid, local_key) VALUES (?, ?)", (card_id, idx+1))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "FirstName", first))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "LastName", last))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "DisplayName", display_name))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "Department", dept))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "PrimaryEmail", email))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, ?, ?)", (card_id, "RecordKey", card_id))

conn.commit()
conn.close()
EOF

# Fix permissions
chown -R ga:ga "$TB_PROFILE"

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile $TB_PROFILE &"
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Focus and Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Dismiss any potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="