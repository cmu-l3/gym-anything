#!/bin/bash
set -e
echo "=== Setting up create_aggregate_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Generate Ground Truth (using Python and the raw SQLite file)
# This ensures we have the correct expected values regardless of DB version
echo "Computing ground truth from Chinook SQLite..."
python3 -c '
import sqlite3
import json
import os

db_path = "/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite"
output_path = "/tmp/ground_truth.json"

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Calculate expected revenue by genre
        cursor.execute("""
            SELECT g.Name, SUM(il.UnitPrice * il.Quantity) as Revenue
            FROM InvoiceLine il
            JOIN Track t ON il.TrackId = t.TrackId
            JOIN Genre g ON t.GenreId = g.GenreId
            GROUP BY g.Name
            ORDER BY Revenue DESC
        """)
        results = cursor.fetchall()
        
        top_genre = results[0][0] if results else "Unknown"
        top_revenue = results[0][1] if results else 0.0
        
        data = {
            "top_genre": top_genre,
            "top_revenue": top_revenue,
            "count": len(results),
            "top_5": [{"genre": r[0], "revenue": r[1]} for r in results[:5]]
        }
        
        with open(output_path, "w") as f:
            json.dump(data, f, indent=2)
            
        print(f"Ground truth computed: Top is {top_genre} (${top_revenue:.2f})")
        conn.close()
    except Exception as e:
        print(f"Error computing ground truth: {e}")
else:
    print(f"SQLite DB not found at {db_path}")
'

# 3. Setup LibreOffice Base
# This utility kills existing instances, restores a fresh chinook.odb,
# launches it, waits for the window, dismisses dialogs, and maximizes.
setup_libreoffice_base_task /home/ga/chinook.odb

# 4. Record initial ODB state
if [ -f /home/ga/chinook.odb ]; then
    stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
    stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt
fi

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="