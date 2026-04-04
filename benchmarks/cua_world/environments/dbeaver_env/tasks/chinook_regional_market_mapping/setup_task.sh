#!/bin/bash
# Setup script for chinook_regional_market_mapping
# Prepares the database and calculates ground truth for verification

set -e
echo "=== Setting up Chinook Regional Market Mapping Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Ensure Chinook database is clean (reset if needed)
if [ ! -f "$CHINOOK_DB" ]; then
    echo "ERROR: Chinook database not found at $CHINOOK_DB"
    exit 1
fi

# Clean up any previous attempts
sqlite3 "$CHINOOK_DB" "DROP VIEW IF EXISTS v_regional_sales;" 2>/dev/null || true
sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS region_mapping;" 2>/dev/null || true
rm -f "$EXPORT_DIR/regional_sales_summary.csv"
rm -f "$SCRIPTS_DIR/create_regions.sql"

# Calculate Ground Truth using Python
# This ensures we have the exact expected revenue numbers based on the current DB state
echo "Calculating ground truth..."
python3 << 'PYEOF'
import sqlite3
import json

db_path = "/home/ga/Documents/databases/chinook.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Mapping Rules
regions = {
    "NA": ["USA", "Canada"],
    "LATAM": ["Brazil", "Chile", "Argentina"],
    "APAC": ["Australia", "India"],
    "EMEA": ["United Kingdom", "Germany", "France", "Czech Republic", "Austria", 
             "Belgium", "Denmark", "Finland", "Hungary", "Ireland", "Italy", 
             "Netherlands", "Norway", "Poland", "Portugal", "Spain", "Sweden"]
}

# Reverse mapping for easy lookup
country_to_region = {}
for code, countries in regions.items():
    for country in countries:
        country_to_region[country] = code

# Get all invoices
cursor.execute("SELECT BillingCountry, Total FROM invoices")
rows = cursor.fetchall()

results = {}

distinct_countries = set()

for country, total in rows:
    distinct_countries.add(country)
    
    # Determine region
    region_code = country_to_region.get(country, "OTH")
    
    if region_code not in results:
        results[region_code] = {"revenue": 0.0, "count": 0}
    
    results[region_code]["revenue"] += total
    results[region_code]["count"] += 1

# Format for output
output = {
    "distinct_country_count": len(distinct_countries),
    "regions": {}
}

for code, data in results.items():
    output["regions"][code] = {
        "revenue": round(data["revenue"], 2),
        "count": data["count"],
        "avg_order": round(data["revenue"] / data["count"], 2) if data["count"] > 0 else 0
    }

# Save ground truth
with open('/tmp/region_ground_truth.json', 'w') as f:
    json.dump(output, f, indent=2)

print("Ground truth calculated:")
print(json.dumps(output, indent=2))
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            break
        fi
        sleep 1
    done
fi

focus_dbeaver || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="