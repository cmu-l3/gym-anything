#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up aggregate_analytics_report task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for OrientDB to be fully ready
wait_for_orientdb 120

# 3. Clean up previous run artifacts
rm -f /home/ga/analytics_report.txt
rm -rf /tmp/ground_truth
mkdir -p /tmp/ground_truth

# 4. Generate GROUND TRUTH data by running the correct queries now.
# We save these to hidden JSON files that the verifier will use to check the agent's work.
# This ensures the verifier is always accurate even if the random seed data changes.

echo "Generating ground truth data..."

# GT 1: Nationality Distribution
orientdb_sql "demodb" "SELECT Nationality, COUNT(*) as cnt FROM Profiles GROUP BY Nationality ORDER BY cnt DESC" \
    > /tmp/ground_truth/nationality.json

# GT 2: Average Hotel Stars (using AVG)
orientdb_sql "demodb" "SELECT Country, AVG(Stars) as avg_stars FROM Hotels GROUP BY Country ORDER BY avg_stars DESC" \
    > /tmp/ground_truth/hotel_stars.json

# GT 3: Five-Star Hotels
orientdb_sql "demodb" "SELECT Name, City, Country FROM Hotels WHERE Stars = 5 ORDER BY Name" \
    > /tmp/ground_truth/luxury_hotels.json

# GT 4: Restaurant Count
orientdb_sql "demodb" "SELECT Country, COUNT(*) as cnt FROM Restaurants GROUP BY Country ORDER BY cnt DESC" \
    > /tmp/ground_truth/restaurants.json

# GT 5: Order Revenue
orientdb_sql "demodb" "SELECT Status, SUM(Price) as revenue, AVG(Price) as avg_price, COUNT(*) as cnt FROM Orders GROUP BY Status" \
    > /tmp/ground_truth/orders.json

# Set permissions so agent can't easily stumble upon them (root owned, readable by root only)
# Note: verifier runs as root/host so it can read them. Agent runs as 'ga'.
chmod -R 700 /tmp/ground_truth

# 5. Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# 6. Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="