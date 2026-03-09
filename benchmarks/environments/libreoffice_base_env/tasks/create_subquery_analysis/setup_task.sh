#!/bin/bash
echo "=== Setting up Create Subquery Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Reset the database to a clean state
echo "Restoring clean database..."
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file hash/size
md5sum /home/ga/chinook.odb > /tmp/initial_odb_hash.txt
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Open the Chinook database in LibreOffice Base."
echo "2. Create the 'TracksNotInPlaylists' query (Tracks not in any playlist)."
echo "3. Create the 'GenresAboveAvgTrackCount' query (Genres with > avg track count)."
echo "4. Create the 'HighValueCustomers' query (Customers spending > avg)."
echo "5. Ensure all queries use Subqueries (NOT EXISTS, nested SELECTs) as requested."