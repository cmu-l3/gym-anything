#!/bin/bash
echo "=== Setting up sqlite_financial_artifact_parsing task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/financial_parsing_result.json /tmp/financial_parsing_gt.json \
      /tmp/financial_parsing_start_time 2>/dev/null || true

for d in /home/ga/Cases/Financial_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Prepare Logical Evidence Folder ───────────────────────────────────────────
EVIDENCE_DIR="/home/ga/evidence/logical_seizure"
rm -rf "$EVIDENCE_DIR" 2>/dev/null || true
mkdir -p "$EVIDENCE_DIR"

echo "Downloading Chinook SQLite Database..."
DB_FILE="$EVIDENCE_DIR/system_config.sys"

# Attempt to download real Chinook DB
wget -q -O "$DB_FILE" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null || true

# Validate it's a real SQLite DB. If download failed, build a minimal valid one.
if ! file "$DB_FILE" 2>/dev/null | grep -qi "SQLite"; then
    echo "WARNING: Failed to download Chinook DB. Generating local synthetic fallback..."
    python3 << 'PYEOF'
import sqlite3
import os
db_path = "/home/ga/evidence/logical_seizure/system_config.sys"
if os.path.exists(db_path): os.remove(db_path)
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("CREATE TABLE customers (CustomerId INTEGER PRIMARY KEY, FirstName TEXT, LastName TEXT, Company TEXT)")
cur.execute("CREATE TABLE invoices (InvoiceId INTEGER PRIMARY KEY, CustomerId INTEGER, InvoiceDate DATETIME, BillingCity TEXT, Total NUMERIC)")
cur.execute("INSERT INTO customers VALUES (1, 'Luís', 'Gonçalves', 'Embraer')")
cur.execute("INSERT INTO customers VALUES (2, 'Leonie', 'Köhler', None)")
cur.execute("INSERT INTO customers VALUES (3, 'François', 'Tremblay', None)")
invoices = [
    (1, 2, '2021-01-01 00:00:00', 'Stuttgart', 1.98),
    (12, 2, '2021-02-11 00:00:00', 'Stuttgart', 3.96),
    (67, 2, '2021-10-02 00:00:00', 'Stuttgart', 8.91),
    (196, 2, '2022-05-19 00:00:00', 'Stuttgart', 1.98),
    (219, 2, '2022-08-21 00:00:00', 'Stuttgart', 3.96),
    (241, 2, '2022-11-23 00:00:00', 'Stuttgart', 5.94),
    (293, 2, '2023-08-04 00:00:00', 'Stuttgart', 10.89)
]
cur.executemany("INSERT INTO invoices VALUES (?, ?, ?, ?, ?)", invoices)
conn.commit()
conn.close()
PYEOF
fi

# Add decoy files to logical folder
echo "System initialized normally. Log level: INFO" > "$EVIDENCE_DIR/system_log.txt"
echo "[Network] timeout=30" > "$EVIDENCE_DIR/network.conf"
echo "Backup scheduled for 03:00 AM" > "$EVIDENCE_DIR/backup_status.txt"
cp /etc/hosts "$EVIDENCE_DIR/hosts.bak" 2>/dev/null || true

chown -R ga:ga "$EVIDENCE_DIR"

# ── Ground Truth Extraction ───────────────────────────────────────────────────
# Query the database dynamically so the verifier matches exactly what the agent sees
echo "Extracting Ground Truth from SQLite database..."
python3 << 'PYEOF'
import sqlite3, json
db_path = "/home/ga/evidence/logical_seizure/system_config.sys"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Get Leonie's CustomerId
cur.execute("SELECT CustomerId FROM customers WHERE FirstName='Leonie' AND LastName LIKE 'K%hler'")
row = cur.fetchone()
cid = row[0] if row else -1

# Get Invoices
cur.execute("SELECT InvoiceId, InvoiceDate, BillingCity, Total FROM invoices WHERE CustomerId=?", (cid,))
invoices = cur.fetchall()
total_spend = sum(r[3] for r in invoices) if invoices else 0.0

gt = {
    "customer_id": cid,
    "invoice_count": len(invoices),
    "total_spend": round(total_spend, 2),
    "invoices": [{"id": r[0], "date": r[1], "city": r[2], "total": r[3]} for r in invoices],
    "obfuscated_file": "system_config.sys"
}

with open("/tmp/financial_parsing_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth Built -> ID: {cid}, Invoices: {len(invoices)}, Total: ${gt['total_spend']}")
PYEOF

# ── Record start time & UI Setup ──────────────────────────────────────────────
date +%s > /tmp/financial_parsing_start_time

kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait for welcome screen
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected"
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 2
done

# Dismiss any splash dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

echo "=== Task Setup Complete ==="