#!/bin/bash
set -e
echo "=== Setting up Chinook Schema Modernization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Generate the legacy database (No FKs, Bad Data)
echo "Generating chinook_legacy.db..."
cat > /tmp/generate_legacy_db.py << 'PYEOF'
import sqlite3
import os

source_db = "/home/ga/Documents/databases/chinook.db"
target_db = "/home/ga/Documents/databases/chinook_legacy.db"

# Ensure target directory exists
os.makedirs(os.path.dirname(target_db), exist_ok=True)

if os.path.exists(target_db):
    os.remove(target_db)

# Basic Schema DDL without Foreign Keys
ddl = {
    "artists": "CREATE TABLE artists (ArtistId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Name NVARCHAR(120))",
    "albums": "CREATE TABLE albums (AlbumId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Title NVARCHAR(160) NOT NULL, ArtistId INTEGER NOT NULL)",
    "customers": "CREATE TABLE customers (CustomerId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, FirstName NVARCHAR(40) NOT NULL, LastName NVARCHAR(20) NOT NULL, Company NVARCHAR(80), Address NVARCHAR(70), City NVARCHAR(40), State NVARCHAR(40), Country NVARCHAR(40), PostalCode NVARCHAR(10), Phone NVARCHAR(24), Fax NVARCHAR(24), Email NVARCHAR(60), SupportRepId INTEGER)",
    "employees": "CREATE TABLE employees (EmployeeId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, LastName NVARCHAR(20) NOT NULL, FirstName NVARCHAR(20) NOT NULL, Title NVARCHAR(30), ReportsTo INTEGER, BirthDate DATETIME, HireDate DATETIME, Address NVARCHAR(70), City NVARCHAR(40), State NVARCHAR(40), Country NVARCHAR(40), PostalCode NVARCHAR(10), Phone NVARCHAR(24), Fax NVARCHAR(24), Email NVARCHAR(60))",
    "genres": "CREATE TABLE genres (GenreId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Name NVARCHAR(120))",
    "invoices": "CREATE TABLE invoices (InvoiceId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, CustomerId INTEGER NOT NULL, InvoiceDate DATETIME NOT NULL, BillingAddress NVARCHAR(70), BillingCity NVARCHAR(40), BillingState NVARCHAR(40), BillingCountry NVARCHAR(40), BillingPostalCode NVARCHAR(10), Total NUMERIC(10,2) NOT NULL)",
    "invoice_items": "CREATE TABLE invoice_items (InvoiceLineId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, InvoiceId INTEGER NOT NULL, TrackId INTEGER NOT NULL, UnitPrice NUMERIC(10,2) NOT NULL, Quantity INTEGER NOT NULL)",
    "media_types": "CREATE TABLE media_types (MediaTypeId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Name NVARCHAR(120))",
    "playlists": "CREATE TABLE playlists (PlaylistId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Name NVARCHAR(120))",
    "playlist_track": "CREATE TABLE playlist_track (PlaylistId INTEGER NOT NULL, TrackId INTEGER NOT NULL, PRIMARY KEY (PlaylistId, TrackId))",
    "tracks": "CREATE TABLE tracks (TrackId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, Name NVARCHAR(200) NOT NULL, AlbumId INTEGER, MediaTypeId INTEGER NOT NULL, GenreId INTEGER, Composer NVARCHAR(220), Milliseconds INTEGER NOT NULL, Bytes INTEGER, UnitPrice NUMERIC(10,2) NOT NULL)"
}

conn_src = sqlite3.connect(source_db)
conn_dst = sqlite3.connect(target_db)
conn_src.row_factory = sqlite3.Row
cur_src = conn_src.cursor()
cur_dst = conn_dst.cursor()

# Create tables and copy data
for table, create_sql in ddl.items():
    cur_dst.execute(create_sql)
    try:
        cur_src.execute(f"SELECT * FROM {table}")
        rows = cur_src.fetchall()
        if rows:
            placeholders = ",".join(["?"] * len(rows[0]))
            cur_dst.executemany(f"INSERT INTO {table} VALUES ({placeholders})", [tuple(row) for row in rows])
    except Exception as e:
        print(f"Skipping data for {table}: {e}")

# Inject Bad Data (Orphans)
# 1. Invoice with invalid CustomerId
cur_dst.execute("INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingCountry, Total) VALUES (9001, 9999, '2023-01-01', 'USA', 9.99)")
cur_dst.execute("INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingCountry, Total) VALUES (9002, 9998, '2023-01-02', 'Canada', 1.99)")

# 2. InvoiceItems for bad invoice (9001) AND completely invalid invoice (9999)
cur_dst.execute("INSERT INTO invoice_items (InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity) VALUES (90001, 9001, 1, 0.99, 1)")
cur_dst.execute("INSERT INTO invoice_items (InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity) VALUES (90002, 9999, 2, 0.99, 1)")

conn_dst.commit()
conn_src.close()
conn_dst.close()
print("Legacy DB generated successfully.")
PYEOF

python3 /tmp/generate_legacy_db.py
rm -f /tmp/generate_legacy_db.py

# Set permissions
chown ga:ga /home/ga/Documents/databases/chinook_legacy.db
chmod 666 /home/ga/Documents/databases/chinook_legacy.db

# Record baseline counts for export comparison
echo "9002" > /tmp/expected_bad_invoice_id
echo "90002" > /tmp/expected_bad_item_id

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="