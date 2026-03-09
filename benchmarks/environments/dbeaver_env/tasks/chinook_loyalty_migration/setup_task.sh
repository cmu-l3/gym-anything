#!/bin/bash
set -e
echo "=== Setting up Chinook Loyalty Migration task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# Create working copy of Chinook database
CHINOOK_SRC="/home/ga/Documents/databases/chinook.db"
CHINOOK_DST="/home/ga/Documents/databases/chinook_loyalty.db"

# Ensure source exists (download if needed, similar to env setup)
if [ ! -f "$CHINOOK_SRC" ]; then
    echo "Downloading source database..."
    wget -q -O "$CHINOOK_SRC" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null || true
fi

# Always create fresh copy for the task
cp "$CHINOOK_SRC" "$CHINOOK_DST"
chmod 644 "$CHINOOK_DST"
chown ga:ga "$CHINOOK_DST"

echo "Created working database at $CHINOOK_DST"

# ------------------------------------------------------------------
# COMPUTE GROUND TRUTH
# We calculate the expected values now based on the clean database
# so we can verify the agent's work later.
# ------------------------------------------------------------------

echo "Computing ground truth..."

# 1. Calculate expected TotalSpend and Tiers for every customer
# Logic: Gold >= 45, Silver >= 38, Bronze >= 30
sqlite3 -header -csv "$CHINOOK_DST" "
SELECT 
    c.CustomerId,
    COALESCE(SUM(i.Total), 0) as ExpectedSpend,
    CASE 
        WHEN COALESCE(SUM(i.Total), 0) >= 45.0 THEN 'Gold'
        WHEN COALESCE(SUM(i.Total), 0) >= 38.0 THEN 'Silver'
        WHEN COALESCE(SUM(i.Total), 0) >= 30.0 THEN 'Bronze'
        ELSE 'None'
    END as ExpectedTier
FROM customers c
LEFT JOIN invoices i ON c.CustomerId = i.CustomerId
GROUP BY c.CustomerId;
" > /tmp/gt_customer_tiers.csv

# 2. Calculate expected Summary Report data
sqlite3 -header -csv "$CHINOOK_DST" "
SELECT
    CASE 
        WHEN COALESCE(SUM(i.Total), 0) >= 45.0 THEN 'Gold'
        WHEN COALESCE(SUM(i.Total), 0) >= 38.0 THEN 'Silver'
        WHEN COALESCE(SUM(i.Total), 0) >= 30.0 THEN 'Bronze'
        ELSE 'None'
    END as LoyaltyTier,
    COUNT(DISTINCT c.CustomerId) as CustomerCount,
    TOTAL(i.Total) as TotalRevenue
FROM customers c
LEFT JOIN invoices i ON c.CustomerId = i.CustomerId
GROUP BY 1;
" > /tmp/gt_summary.csv

# 3. Calculate expected reward row count (Customers with tier != None)
# (Gold+Silver+Bronze count)
EXPECTED_REWARD_ROWS=$(sqlite3 "$CHINOOK_DST" "
SELECT COUNT(*) FROM (
    SELECT c.CustomerId, SUM(i.Total) as total
    FROM customers c JOIN invoices i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
    HAVING total >= 30.0
);")
echo "$EXPECTED_REWARD_ROWS" > /tmp/gt_reward_count.txt

# Secure ground truth files
chmod 600 /tmp/gt_*.csv /tmp/gt_*.txt

# ------------------------------------------------------------------
# UI SETUP
# ------------------------------------------------------------------

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait loop
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "dbeaver" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss potential dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="