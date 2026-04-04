#!/bin/bash
# Setup script for chinook_dedup_cleanup
# Creates a corrupted database with duplicates and shifted foreign keys

set -e
echo "=== Setting up Chinook Dedup Cleanup Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_ORIG="/home/ga/Documents/databases/chinook.db"
CHINOOK_DEDUP="/home/ga/Documents/databases/chinook_dedup.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# ensure directories
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Prepare clean slate
rm -f "$CHINOOK_DEDUP"
rm -f "$EXPORT_DIR/dedup_report.csv"
rm -f "$SCRIPTS_DIR/dedup_cleanup.sql"

# 2. Copy original DB
if [ ! -f "$CHINOOK_ORIG" ]; then
    echo "ERROR: Original Chinook DB not found."
    exit 1
fi
cp "$CHINOOK_ORIG" "$CHINOOK_DEDUP"
chown ga:ga "$CHINOOK_DEDUP"

echo "Injecting duplicates into chinook_dedup.db..."

# 3. Inject Duplicates using Python for easier logic
# We need to:
#  - Insert copies of specific customers/artists
#  - Update some invoices/albums to point to the new copies
#  - Track exactly what we did for verification

python3 << 'PYEOF'
import sqlite3
import json
import shutil

db_path = "/home/ga/Documents/databases/chinook_dedup.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# --- DUPLICATE CUSTOMERS ---
# We will duplicate 8 customers.
# Target IDs to duplicate: 1, 5, 10, 15, 20, 25, 30, 35
target_cust_ids = [1, 5, 10, 15, 20, 25, 30, 35]
customer_map = {} # map original_id -> new_id
invoices_moved = 0

print("Duplicating Customers...")
for old_id in target_cust_ids:
    # Get original data
    c.execute("SELECT * FROM customers WHERE CustomerId=?", (old_id,))
    row = c.fetchone()
    if row:
        # Insert copy (CustomerId is AUTOINCREMENT, so pass NULL/None for it)
        # Schema: CustomerId, FirstName, LastName... 
        # We slice row[1:] to skip ID
        placeholders = ','.join(['?'] * len(row[1:]))
        c.execute(f"INSERT INTO customers (FirstName, LastName, Company, Address, City, State, Country, PostalCode, Phone, Fax, Email, SupportRepId) VALUES ({placeholders})", row[1:])
        new_id = c.lastrowid
        customer_map[old_id] = new_id
        
        # Move 1 invoice from old_id to new_id to simulate data corruption
        # Find an invoice
        c.execute("SELECT InvoiceId FROM invoices WHERE CustomerId=? LIMIT 1", (old_id,))
        inv_row = c.fetchone()
        if inv_row:
            inv_id = inv_row[0]
            c.execute("UPDATE invoices SET CustomerId=? WHERE InvoiceId=?", (new_id, inv_id))
            invoices_moved += 1

# --- DUPLICATE ARTISTS ---
# We will duplicate 6 artists.
# Target IDs: 1 (AC/DC), 50 (Metallica), 90 (Iron Maiden), 100, 110, 120
target_artist_ids = [1, 50, 90, 100, 110, 120]
artist_map = {}
albums_moved = 0

print("Duplicating Artists...")
for old_id in target_artist_ids:
    c.execute("SELECT Name FROM artists WHERE ArtistId=?", (old_id,))
    row = c.fetchone()
    if row:
        name = row[0]
        c.execute("INSERT INTO artists (Name) VALUES (?)", (name,))
        new_id = c.lastrowid
        artist_map[old_id] = new_id
        
        # Move 1 album
        c.execute("SELECT AlbumId FROM albums WHERE ArtistId=? LIMIT 1", (old_id,))
        alb_row = c.fetchone()
        if alb_row:
            alb_id = alb_row[0]
            c.execute("UPDATE albums SET ArtistId=? WHERE AlbumId=?", (new_id, alb_id))
            albums_moved += 1

conn.commit()

# --- VERIFY STATE ---
c.execute("SELECT COUNT(*) FROM customers")
count_cust = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM artists")
count_art = c.fetchone()[0]

ground_truth = {
    "expected_customers": 59,
    "expected_artists": 275,
    "injected_customers": len(customer_map),
    "injected_artists": len(artist_map),
    "invoices_reassigned": invoices_moved,
    "albums_reassigned": albums_moved,
    "customer_dup_map": customer_map,
    "artist_dup_map": artist_map
}

with open('/tmp/dedup_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f"Injection complete. Customers: {count_cust} (Expected 67). Artists: {count_art} (Expected 281).")
conn.close()
PYEOF

# 4. Record Initial State for verifier
cp /tmp/dedup_ground_truth.json /tmp/initial_state.json

# 5. Timestamp
date +%s > /tmp/task_start_time

# 6. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 10
fi

# 7. Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="