#!/bin/bash
# Setup script for chinook_viral_track_analysis
# Creates a database with specific sales patterns to test advanced SQL logic

set -e
echo "=== Setting up Chinook Viral Track Analysis ==="

source /workspace/scripts/task_utils.sh

# Configuration
SRC_DB="/workspace/data/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_viral.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Clean start
rm -rf "$EXPORT_DIR" "$SCRIPTS_DIR"
mkdir -p "$(dirname "$TARGET_DB")" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# 1. Create the Viral Database
echo "Creating viral database..."
cp "$SRC_DB" "$TARGET_DB"

# 2. Inject Viral Data
# Scenario: 
# Album 1 ("For Those About To Rock We Salute You") has 10 tracks.
# We will inject massive sales for Track 1, small sales for Track 6, and 0 for others.
# This ensures that a correct AVG calculation (including 0s) is distinct from an incorrect one (excluding 0s).

sqlite3 "$TARGET_DB" <<EOF
-- Create a new high-value invoice
INSERT INTO invoices (CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, Total)
VALUES (1, '2023-01-01', 'Viral St', 'New York', 'USA', 1000.00);

-- Get the ID (assuming it's the max now)
-- Inject 150 copies of Track 1 (Viral Hit)
INSERT INTO invoice_items (InvoiceId, TrackId, UnitPrice, Quantity)
SELECT MAX(InvoiceId), 1, 0.99, 150 FROM invoices; 

-- Inject 5 copies of Track 6 (Minor Hit)
INSERT INTO invoice_items (InvoiceId, TrackId, UnitPrice, Quantity)
SELECT MAX(InvoiceId), 6, 0.99, 5 FROM invoices; 

-- Scenario 2: Album 4 ("Let There Be Rock")
-- Track 23 gets a spike, but maybe not enough to be 3x if the average is high
INSERT INTO invoices (CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, Total)
VALUES (2, '2023-01-02', 'Test Ave', 'London', 'UK', 50.00);

INSERT INTO invoice_items (InvoiceId, TrackId, UnitPrice, Quantity)
SELECT MAX(InvoiceId), 23, 0.99, 40 FROM invoices; 
EOF

# Set permissions
chown ga:ga "$TARGET_DB"
chmod 644 "$TARGET_DB"

# 3. Calculate Ground Truth (Hidden)
# We calculate what the answer *should* be to compare later
# This complex query mirrors the solution logic to generate a ground truth file
echo "Calculating ground truth..."
sqlite3 -header -csv "$TARGET_DB" "
WITH TrackSales AS (
    SELECT 
        t.AlbumId,
        t.TrackId,
        t.Name AS TrackName,
        IFNULL(SUM(ii.UnitPrice * ii.Quantity), 0) as TrackRevenue
    FROM tracks t
    LEFT JOIN invoice_items ii ON t.TrackId = ii.TrackId
    GROUP BY t.AlbumId, t.TrackId
),
AlbumStats AS (
    SELECT
        AlbumId,
        AVG(TrackRevenue) as AlbumAvgRevenue
    FROM TrackSales
    GROUP BY AlbumId
)
SELECT 
    a.Title as AlbumTitle,
    ts.TrackName,
    ROUND(ts.TrackRevenue, 2) as TrackRevenue,
    ROUND(ast.AlbumAvgRevenue, 2) as AlbumAvgRevenue,
    ROUND(ts.TrackRevenue / ast.AlbumAvgRevenue, 2) as RevenueMultiplier
FROM TrackSales ts
JOIN AlbumStats ast ON ts.AlbumId = ast.AlbumId
JOIN albums a ON ts.AlbumId = a.AlbumId
WHERE ts.TrackRevenue > (3.0 * ast.AlbumAvgRevenue)
ORDER BY RevenueMultiplier DESC;
" > /tmp/ground_truth.csv

echo "Ground truth generated with $(wc -l < /tmp/ground_truth.csv) lines (including header)."

# 4. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for DBeaver
    for i in {1..30}; do
        if is_dbeaver_running; then
            break
        fi
        sleep 1
    done
fi

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="