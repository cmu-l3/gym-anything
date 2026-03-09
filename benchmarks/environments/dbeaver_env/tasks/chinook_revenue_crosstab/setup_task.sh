#!/bin/bash
# Setup script for chinook_revenue_crosstab task
set -e

echo "=== Setting up Chinook Revenue Crosstab Task ==="

source /workspace/scripts/task_utils.sh

# Paths
CHINOOK_SRC="/home/ga/Documents/databases/chinook.db"
CHINOOK_WORK="/home/ga/Documents/databases/chinook_crosstab.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Clean up previous artifacts
rm -f "$EXPORT_DIR/genre_yearly_revenue.csv"
rm -f "$SCRIPTS_DIR/genre_crosstab.sql"
rm -f "$CHINOOK_WORK"

# Create working copy of database
if [ -f "$CHINOOK_SRC" ]; then
    cp "$CHINOOK_SRC" "$CHINOOK_WORK"
    chmod 666 "$CHINOOK_WORK"
    chown ga:ga "$CHINOOK_WORK"
    echo "Created working database copy at $CHINOOK_WORK"
else
    echo "ERROR: Source database not found at $CHINOOK_SRC"
    exit 1
fi

# Calculate Ground Truth using sqlite3
# We calculate the Rock revenue for 2009 and Total to verify against agent's output later
echo "Calculating ground truth..."
sqlite3 "$CHINOOK_WORK" <<EOF > /tmp/ground_truth_values.json
.mode json
SELECT 
    'Rock' as genre,
    SUM(CASE WHEN strftime('%Y', i.InvoiceDate) = '2009' THEN il.UnitPrice * il.Quantity ELSE 0 END) as rev_2009,
    SUM(il.UnitPrice * il.Quantity) as total_revenue
FROM Genre g
JOIN Track t ON g.GenreId = t.GenreId
JOIN InvoiceLine il ON t.TrackId = il.TrackId
JOIN Invoice i ON il.InvoiceId = i.InvoiceId
WHERE g.Name = 'Rock';
EOF

# Determine distinct genre count for row count verification
GENRE_COUNT=$(sqlite3 "$CHINOOK_WORK" "SELECT COUNT(DISTINCT g.GenreId) FROM Genre g JOIN Track t ON g.GenreId = t.GenreId JOIN InvoiceLine il ON t.TrackId = il.TrackId;")
echo "$GENRE_COUNT" > /tmp/ground_truth_genre_count.txt

echo "Ground truth calculated. Genre count: $GENRE_COUNT"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="