#!/bin/bash
echo "=== Setting up Create Reservation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure Docker containers are running
echo "Checking Booked Scheduler containers..."
if ! docker ps | grep -q booked-db; then
    echo "ERROR: Booked DB container not running!"
    exit 1
fi

# Wait for Booked to be accessible
wait_for_booked

# Record initial reservation count (anti-gaming: do-nothing must fail)
INITIAL_COUNT=$(get_reservation_count)
echo "$INITIAL_COUNT" > /tmp/initial_reservation_count
chmod 666 /tmp/initial_reservation_count
echo "Initial reservation count: $INITIAL_COUNT"

# Ensure no reservation with this title already exists for tomorrow
echo "Cleaning up any existing test reservation..."
booked_db_query "DELETE rs FROM reservation_series rs
    INNER JOIN reservation_instances ri ON rs.series_id = ri.series_id
    WHERE rs.title = 'Python Advanced Workshop'
    AND DATE(ri.start_date) = DATE_ADD(CURDATE(), INTERVAL 1 DAY)" 2>/dev/null || true

# Verify cleanup
NEW_COUNT=$(get_reservation_count)
echo "Reservation count after cleanup: $NEW_COUNT"
echo "$NEW_COUNT" > /tmp/initial_reservation_count
chmod 666 /tmp/initial_reservation_count

# Ensure Firefox is running and pointed to the Booked schedule page
ensure_firefox_running "$BOOKED_SCHEDULE_URL"
sleep 3

# Focus and maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Create Reservation Task Setup Complete ==="
echo ""
echo "TASK: Create a new reservation in Booked Scheduler"
echo ""
echo "Instructions:"
echo "  1. Log in to Booked Scheduler (admin / password)"
echo "  2. Navigate to the schedule view"
echo "  3. Book 'Training Room Alpha' for tomorrow 2:00 PM - 4:00 PM"
echo "  4. Title: 'Python Advanced Workshop'"
echo "  5. Description: 'Intermediate-to-advanced Python workshop covering decorators, generators, and async patterns.'"
echo "  6. Save the reservation"
echo ""
echo "Initial reservation count: $NEW_COUNT"
