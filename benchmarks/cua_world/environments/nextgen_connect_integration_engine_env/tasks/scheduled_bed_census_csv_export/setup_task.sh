#!/bin/bash
set -e
echo "=== Setting up Scheduled Bed Census CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Create output directory and ensure it's writable
mkdir -p /home/ga/reports
chmod 777 /home/ga/reports
# Remove any existing report to prevent false positives
rm -f /home/ga/reports/census_report.csv

# Wait for Postgres to be ready
echo "Waiting for PostgreSQL..."
until docker exec nextgen-postgres pg_isready -U postgres >/dev/null 2>&1; do
    sleep 1
done

# Seed the database with hospital bed census data
echo "Seeding database table 'bed_census'..."
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS bed_census;
CREATE TABLE bed_census (
    id SERIAL PRIMARY KEY,
    unit_name VARCHAR(50),
    total_beds INTEGER,
    occupied_beds INTEGER
);

INSERT INTO bed_census (unit_name, total_beds, occupied_beds) VALUES
('ICU', 20, 18),      -- 18/20 = 90.0% (CRITICAL)
('ER', 50, 48),       -- 48/50 = 96.0% (CRITICAL)
('MEDSURG', 100, 75), -- 75/100 = 75.0% (NORMAL)
('PEDS', 30, 5),      -- 5/30 = 16.666...% -> 16.7% (NORMAL)
('NICU', 15, 14);     -- 14/15 = 93.333...% -> 93.3% (CRITICAL)
"

# Open Firefox to NextGen Connect landing page
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="