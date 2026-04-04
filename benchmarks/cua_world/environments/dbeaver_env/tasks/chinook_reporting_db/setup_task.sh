#!/bin/bash
# Setup script for chinook_reporting_db task
# Pre-calculates ground truth values from the source database for verification

set -e
echo "=== Setting up Chinook Reporting DB Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
REPORT_DB="/home/ga/Documents/databases/chinook_reports.db"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$(dirname "$REPORT_DB")"
mkdir -p "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up any previous task artifacts to ensure fresh start
rm -f "$REPORT_DB"
rm -f "$SCRIPTS_DIR/create_reports_db.sql"

# Verify source database exists
if [ ! -f "$CHINOOK_DB" ]; then
    echo "ERROR: Source Chinook database not found at $CHINOOK_DB"
    # Try to restore it using the setup_dbeaver.sh logic if missing
    /workspace/scripts/setup_dbeaver.sh
fi

# Calculate Ground Truth values from Source DB
echo "Calculating ground truth from source..."

# 1. Artist Summary Ground Truth
# Iron Maiden (ArtistId=90) stats
GT_IRON_MAIDEN=$(sqlite3 "$CHINOOK_DB" "
SELECT 
    COUNT(DISTINCT a.AlbumId) || '|' || 
    COUNT(t.TrackId) || '|' || 
    printf('%.2f', SUM(t.Milliseconds)/60000.0) 
FROM artists ar
JOIN albums a ON ar.ArtistId = a.ArtistId
JOIN tracks t ON a.AlbumId = t.AlbumId
WHERE ar.Name = 'Iron Maiden';")

# Total Artist Count
GT_ARTIST_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM artists;")

# 2. Genre Revenue Ground Truth
# Top Genre Revenue (Rock is usually #1)
GT_TOP_GENRE=$(sqlite3 "$CHINOOK_DB" "
SELECT 
    g.Name || '|' || 
    printf('%.2f', SUM(ii.UnitPrice * ii.Quantity))
FROM genres g
JOIN tracks t ON g.GenreId = t.GenreId
JOIN invoice_items ii ON t.TrackId = ii.TrackId
GROUP BY g.GenreId
ORDER BY SUM(ii.UnitPrice * ii.Quantity) DESC
LIMIT 1;")

# Total Revenue across all genres
GT_TOTAL_REVENUE=$(sqlite3 "$CHINOOK_DB" "SELECT printf('%.2f', SUM(Total)) FROM invoices;")

# 3. Monthly Sales Ground Truth
# Count of months with sales
GT_MONTH_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(DISTINCT strftime('%Y-%m', InvoiceDate)) FROM invoices;")

# Save Ground Truth to JSON
cat > /tmp/chinook_gt.json << EOF
{
    "artist_count": $GT_ARTIST_COUNT,
    "iron_maiden_stats": "$GT_IRON_MAIDEN",
    "top_genre_stats": "$GT_TOP_GENRE",
    "total_revenue": "$GT_TOTAL_REVENUE",
    "month_count": $GT_MONTH_COUNT
}
EOF

echo "Ground Truth Calculated:"
cat /tmp/chinook_gt.json

# Record start time for anti-gaming
date +%s > /tmp/task_start_time

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" > /dev/null 2>&1 &
    sleep 10
fi

focus_dbeaver || true
maximize_window "DBeaver" || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="