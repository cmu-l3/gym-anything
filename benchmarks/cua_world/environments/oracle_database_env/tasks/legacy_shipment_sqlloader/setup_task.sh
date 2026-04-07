#!/bin/bash
# Setup for Legacy Shipment SQL*Loader task
# Generates the fixed-width data file and ensures clean database state

set -e

echo "=== Setting up Legacy Shipment SQL*Loader Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "Cleaning up database..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE shipment_history CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/shipment_logs.dat
rm -f /home/ga/Desktop/load_shipments.ctl
rm -f /home/ga/shipment_logs.log
rm -f /home/ga/shipment_logs.bad

# --- Generate Fixed Width Data File ---
echo "Generating legacy data file..."

python3 << 'PYEOF'
import random
import datetime

# Configuration
VALID_COUNT = 45
VOID_COUNT = 5
OUTPUT_FILE = "/home/ga/Desktop/shipment_logs.dat"

# Airports
AIRPORTS = ["JFK", "LHR", "HND", "DXB", "LAX", "CDG", "SIN", "FRA", "AMS", "IST"]

# Generate data
lines = []
lines.append("SHIPMENT LOG FILE - GENERATED " + datetime.datetime.now().strftime("%Y-%m-%d"))
lines.append("ID        ORGDESTDATE    WGT   COST      ST")
# Format: 1-10 ID, 11-13 ORG, 14-16 DST, 17-24 DATE, 25-30 WGT, 31-40 COST, 41-42 ST

total_valid_cost = 0

# Create mixed list of valid and void records
records = []
for i in range(VALID_COUNT + VOID_COUNT):
    is_void = i < VOID_COUNT # First 5 are void (will shuffle later)
    
    ship_id = f"{10000 + i:010d}"
    org = random.choice(AIRPORTS)
    dest = random.choice([a for a in AIRPORTS if a != org])
    
    # Date between 2020-01-01 and 2023-12-31
    start_date = datetime.date(2020, 1, 1)
    end_date = datetime.date(2023, 12, 31)
    days_between = (end_date - start_date).days
    random_days = random.randrange(days_between)
    date_obj = start_date + datetime.timedelta(days=random_days)
    date_str = date_obj.strftime("%Y%m%d")
    
    weight = f"{random.randint(50, 5000):06d}"
    
    # Cost: Implied 2 decimals. 
    # e.g. 12345 -> 123.45
    # Generate integer cost
    cost_int = random.randint(1000, 200000)
    cost_str = f"{cost_int:010d}"
    
    if is_void:
        status = "99"
    else:
        status = random.choice(["00", "10", "20"])
        total_valid_cost += (cost_int / 100.0)
        
    line = f"{ship_id}{org}{dest}{date_str}{weight}{cost_str}{status}"
    records.append(line)

# Shuffle records so voids aren't all at top
random.shuffle(records)
lines.extend(records)

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

# Save expected metadata for verifier
with open("/tmp/expected_shipment_data.json", "w") as f:
    import json
    json.dump({
        "valid_count": VALID_COUNT,
        "void_count": VOID_COUNT,
        "total_valid_cost": round(total_valid_cost, 2)
    }, f)

print(f"Generated {len(records)} records ({VALID_COUNT} valid, {VOID_COUNT} void)")
print(f"Total Expected Valid Cost: {total_valid_cost:.2f}")
PYEOF

# Record start time
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp
chmod 644 /tmp/expected_shipment_data.json

# Take start screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="