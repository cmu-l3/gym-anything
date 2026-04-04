#!/bin/bash
# Setup script for chinook_storage_optimization task
# Generates a bloated SQLite database with known distribution of old/new records

set -e
echo "=== Setting up Chinook Storage Optimization Task ==="

source /workspace/scripts/task_utils.sh

DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
DB_PATH="$DB_DIR/chinook_bloated.db"

mkdir -p "$DB_DIR" "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove previous artifacts
rm -f "$DB_PATH"
rm -f "$EXPORT_DIR/audit_archive.csv"

# Record start time
date +%s > /tmp/task_start_time.txt

echo "Generating bloated database (this may take 15-30 seconds)..."

# Python script to generate specific data patterns
python3 -c '
import sqlite3
import random
import string
import os

# Deterministic seed for consistent generation per run, but unique enough
random.seed(42)

db_path = "/home/ga/Documents/databases/chinook_bloated.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create table
c.execute("CREATE TABLE IF NOT EXISTS audit_logs (id INTEGER PRIMARY KEY, log_date TEXT, severity TEXT, message TEXT)")

# Generate ~40MB of data
# We want roughly 40,000 rows.
# Split: ~26,000 old (pre-2024), ~14,000 new (2024+)
# Payload per row ~1KB

total_rows = 40000
chunk_size = 5000
filler = "".join(random.choices(string.ascii_letters, k=1000))

pre_2024_count = 0
post_2024_count = 0
records = []

print("  - Inserting records...")
for i in range(total_rows):
    # Weighted random to favor old data slightly (2:1)
    year = random.choices(["2022", "2023", "2024"], weights=[1, 1, 1], k=1)[0]
    month = f"{random.randint(1,12):02d}"
    day = f"{random.randint(1,28):02d}"
    date = f"{year}-{month}-{day}"
    
    if year < "2024":
        pre_2024_count += 1
    else:
        post_2024_count += 1
        
    severity = random.choice(["INFO", "WARN", "ERROR"])
    msg = f"{i}:{filler}"[:1000] # Ensure roughly constant size
    records.append((date, severity, msg))
    
    if len(records) >= chunk_size:
        c.executemany("INSERT INTO audit_logs (log_date, severity, message) VALUES (?, ?, ?)", records)
        conn.commit()
        records = []

if records:
    c.executemany("INSERT INTO audit_logs (log_date, severity, message) VALUES (?, ?, ?)", records)
    conn.commit()

# Create indexes to make the file structure realistic/fragmented
c.execute("CREATE INDEX idx_date ON audit_logs(log_date)")
c.execute("CREATE INDEX idx_severity ON audit_logs(severity)")

conn.commit()
conn.close()

# Save ground truth counts for verification
with open("/tmp/initial_counts.txt", "w") as f:
    f.write(f"{pre_2024_count},{post_2024_count}")

print(f"  - Database generated: {pre_2024_count} old records, {post_2024_count} new records.")
'

# Set ownership
chown ga:ga "$DB_PATH"

# Record initial file size
INITIAL_SIZE=$(stat -c%s "$DB_PATH" 2>/dev/null || echo 0)
echo "$INITIAL_SIZE" > /tmp/initial_db_size.txt
echo "Initial DB size: $((INITIAL_SIZE / 1024 / 1024)) MB"

# Launch DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="