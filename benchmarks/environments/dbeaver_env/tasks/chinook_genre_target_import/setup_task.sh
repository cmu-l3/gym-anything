#!/bin/bash
# Setup script for chinook_genre_target_import
# Generates deterministic sales target data and sets up the environment

set -e
echo "=== Setting up Chinook Genre Target Import Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
IMPORT_DIR="/home/ga/Documents/imports"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
TARGET_CSV="$IMPORT_DIR/genre_sales_targets.csv"
GROUND_TRUTH_FILE="/tmp/ground_truth_variance.json"

# Ensure directories exist
mkdir -p "$IMPORT_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Ensure Chinook database exists (from env setup)
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Attempt fallback copy if available in standard location
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$DB_PATH"
    else
        echo "CRITICAL: Cannot proceed without database."
        exit 1
    fi
fi

# Clean previous artifacts
rm -f "$TARGET_CSV"
rm -f "$EXPORT_DIR/genre_variance_report.csv"
rm -f "$SCRIPTS_DIR/genre_variance_analysis.sql"

# Generate Target CSV and Ground Truth Data using Python
# This ensures targets are based on actual data with deterministic variance
echo "Generating sales targets and ground truth..."
python3 -c "
import sqlite3
import csv
import json
import hashlib
import os

db_path = '$DB_PATH'
csv_path = '$TARGET_CSV'
gt_path = '$GROUND_TRUTH_FILE'

def get_growth_factor(genre, year):
    # Deterministic hash to get a float between 0.8 and 1.2
    key = f'{genre}_{year}'
    hash_val = int(hashlib.md5(key.encode()).hexdigest(), 16)
    # Map to 0.8 to 1.25 range
    factor = 0.8 + (hash_val % 450) / 1000.0
    return factor

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Query Actual Revenue
    query = '''
    SELECT 
        g.Name as GenreName,
        STRFTIME('%Y', i.InvoiceDate) as Year,
        SUM(ii.UnitPrice * ii.Quantity) as ActualRevenue
    FROM invoice_items ii
    JOIN tracks t ON ii.TrackId = t.TrackId
    JOIN genres g ON t.GenreId = g.GenreId
    JOIN invoices i ON ii.InvoiceId = i.InvoiceId
    GROUP BY g.Name, Year
    ORDER BY g.Name, Year
    '''
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    targets = []
    ground_truth = []
    
    # Header for CSV
    targets.append(['GenreName', 'Year', 'TargetRevenue'])
    
    for row in rows:
        genre = row[0]
        year = int(row[1])
        actual = float(row[2])
        
        # Calculate target
        factor = get_growth_factor(genre, year)
        target = round(actual * factor, 2)
        
        # Add to CSV list
        targets.append([genre, year, target])
        
        # Calculate ground truth variance
        variance = round(actual - target, 2)
        if target != 0:
            variance_pct = round((variance / target) * 100, 2)
        else:
            variance_pct = 0.0
            
        ground_truth.append({
            'GenreName': genre,
            'Year': year,
            'TargetRevenue': target,
            'ActualRevenue': round(actual, 2),
            'Variance': variance,
            'VariancePct': variance_pct
        })

    # Write CSV
    with open(csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(targets)
    
    # Write Ground Truth
    with open(gt_path, 'w') as f:
        json.dump(ground_truth, f, indent=2)
        
    print(f'Generated {len(targets)-1} target rows.')
    conn.close()

except Exception as e:
    print(f'Error generating data: {e}')
    exit(1)
"

# Set permissions
chown ga:ga "$TARGET_CSV"
chmod 644 "$TARGET_CSV"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="