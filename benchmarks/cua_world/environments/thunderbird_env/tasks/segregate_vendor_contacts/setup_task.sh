#!/bin/bash
echo "=== Setting up Segregate Vendor Contacts task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can safely modify the SQLite DB
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing Thunderbird..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 1
fi

PROFILE_DIR="/home/ga/.thunderbird/default-release"
mkdir -p "$PROFILE_DIR"

# Python script to cleanly initialize the address book with the Enron dataset
cat > /tmp/init_address_book.py << 'EOF'
import sqlite3
import os

db_path = "/home/ga/.thunderbird/default-release/abook.sqlite"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Ensure the properties schema exists
c.execute("CREATE TABLE IF NOT EXISTS properties (card INTEGER, name TEXT, value TEXT)")
c.execute("DELETE FROM properties")

contacts = [
    # Internal Contacts
    ("Kenneth", "Lay", "kenneth.lay@enron.com"),
    ("Jeffrey", "Skilling", "jeffrey.skilling@enron.com"),
    ("Andrew", "Fastow", "andrew.fastow@enron.com"),
    ("Richard", "Causey", "richard.causey@enron.com"),
    ("Rebecca", "Mark", "rebecca.mark@enron.com"),
    ("Lou", "Pai", "lou.pai@enron.com"),
    ("Cliff", "Baxter", "cliff.baxter@enron.com"),
    ("Sherron", "Watkins", "sherron.watkins@enron.com"),
    ("Amanda", "Martin", "amanda.martin@enron.com"),
    # External Vendor Contacts (Targets)
    ("Vince", "Kaminski", "j.kaminski@yahoo.com"),
    ("Vincent", "Kaminski", "vkaminski@aol.com"),
    ("Shirley", "Crenshaw", "shirley.crenshaw@wcom.com")
]

for i, (fn, ln, email) in enumerate(contacts, 1):
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, 'FirstName', ?)", (i, fn))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, 'LastName', ?)", (i, ln))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, 'DisplayName', ?)", (i, f"{fn} {ln}"))
    c.execute("INSERT INTO properties (card, name, value) VALUES (?, 'PrimaryEmail', ?)", (i, email))

conn.commit()
conn.close()
print("Initialized abook.sqlite with 12 Enron contacts.")
EOF

# Run the python initialization script
python3 /tmp/init_address_book.py
chown ga:ga "$PROFILE_DIR/abook.sqlite"

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile $PROFILE_DIR &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="