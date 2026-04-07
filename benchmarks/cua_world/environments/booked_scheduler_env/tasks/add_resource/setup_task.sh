#!/bin/bash
echo "=== Setting up Add Resource Task ==="

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

# Record initial resource count (anti-gaming: do-nothing must fail)
INITIAL_COUNT=$(get_resource_count)
echo "$INITIAL_COUNT" > /tmp/initial_resource_count
chmod 666 /tmp/initial_resource_count
echo "Initial resource count: $INITIAL_COUNT"

# Ensure the target resource doesn't already exist
echo "Cleaning up any existing 'Rooftop Terrace' resource..."
booked_db_query "DELETE FROM resources WHERE LOWER(TRIM(name)) = 'rooftop terrace'" 2>/dev/null || true

# Update count after cleanup
NEW_COUNT=$(get_resource_count)
echo "Resource count after cleanup: $NEW_COUNT"
echo "$NEW_COUNT" > /tmp/initial_resource_count
chmod 666 /tmp/initial_resource_count

# Ensure Firefox is running on the admin resources page
ensure_firefox_running "$BOOKED_ADMIN_URL"
sleep 3

# Focus and maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Add Resource Task Setup Complete ==="
echo ""
echo "TASK: Add a new resource to Booked Scheduler"
echo ""
echo "Instructions:"
echo "  1. Log in as admin (admin / password)"
echo "  2. Navigate to Application Management > Resources"
echo "  3. Click 'Add a New Resource' (or similar button)"
echo "  4. Fill in:"
echo "     - Name: 'Rooftop Terrace'"
echo "     - Location: 'Building A, Rooftop Level'"
echo "     - Contact: 'facilities@acmecorp.com'"
echo "     - Description: 'Open-air meeting space with city views, retractable awning, and built-in speakers. Capacity 25 guests.'"
echo "     - Max Participants: 25"
echo "     - Allow Multi-day Reservations: Yes"
echo "  5. Save the resource"
echo ""
echo "Initial resource count: $NEW_COUNT"
