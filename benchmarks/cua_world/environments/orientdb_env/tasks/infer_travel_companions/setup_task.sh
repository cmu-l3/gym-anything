#!/bin/bash
echo "=== Setting up infer_travel_companions task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# 1. Reset 'PotentialCompanion' class (Drop if exists)
if orientdb_class_exists "demodb" "PotentialCompanion"; then
    echo "Dropping existing PotentialCompanion class..."
    orientdb_sql "demodb" "DROP CLASS PotentialCompanion UNSAFE" > /dev/null
fi

# 2. Clean up specific seed reviews if they exist from previous runs
# We need to find reviews by John or Maria on 2023-12-25 and delete them to ensure a clean slate
# This requires a bit of traversal logic, but we can approximate by deleting Reviews with that specific text/date
echo "Cleaning up any pre-existing scenario data..."

# Delete reviews with the specific date to be safe
orientdb_sql "demodb" "DELETE VERTEX Reviews WHERE Date = '2023-12-25'" > /dev/null

# 3. Ensure required vertices exist (Profiles and Hotel)
# John Smith
count_john=$(orientdb_sql "demodb" "SELECT count(*) as c FROM Profiles WHERE Email='john.smith@example.com'" | grep -o '"c":[0-9]*' | cut -d: -f2)
if [ "$count_john" == "0" ]; then
    echo "Restoring John Smith profile..."
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='john.smith@example.com', Name='John', Surname='Smith', Gender='Male', Birthday='1985-03-15', Nationality='American'" > /dev/null
fi

# Maria Garcia
count_maria=$(orientdb_sql "demodb" "SELECT count(*) as c FROM Profiles WHERE Email='maria.garcia@example.com'" | grep -o '"c":[0-9]*' | cut -d: -f2)
if [ "$count_maria" == "0" ]; then
    echo "Restoring Maria Garcia profile..."
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='maria.garcia@example.com', Name='Maria', Surname='Garcia', Gender='Female', Birthday='1990-07-22', Nationality='Spanish'" > /dev/null
fi

# Hotel Artemide
count_hotel=$(orientdb_sql "demodb" "SELECT count(*) as c FROM Hotels WHERE Name='Hotel Artemide'" | grep -o '"c":[0-9]*' | cut -d: -f2)
if [ "$count_hotel" == "0" ]; then
    echo "Restoring Hotel Artemide..."
    orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Artemide', City='Rome', Country='Italy', Stars=4" > /dev/null
fi

# 4. Launch Firefox to Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Capture initial state screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="